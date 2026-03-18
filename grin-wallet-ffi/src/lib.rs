//! Grin Wallet FFI — thin C-callable layer for iOS integration.
//!
//! All functions return JSON strings (caller must free with `grin_str_free`).
//! Errors are returned as JSON: `{"error": "message"}`.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::mpsc::channel;

use grin_wallet_api::{Foreign, Owner};
use grin_wallet_config::WALLET_CONFIG_FILE_NAME;
use grin_wallet_impls::{DefaultLCProvider, DefaultWalletImpl, HTTPNodeClient};
use grin_wallet_libwallet::{
    IssueInvoiceTxArgs, InitTxArgs,
    NodeClient, Slatepacker, SlatepackerArgs,
    WalletInst, WalletLCProvider,
    api_impl::owner_updater::StatusMessage,
};
use grin_core::global::{self, ChainTypes};
use grin_keychain::{self, ExtKeychain};
use grin_util::{Mutex, ZeroingString};

type Wallet = Arc<
    Mutex<
        Box<
            dyn WalletInst<
                'static,
                DefaultLCProvider<'static, HTTPNodeClient, ExtKeychain>,
                HTTPNodeClient,
                ExtKeychain,
            >,
        >,
    >,
>;

// ─── Cached wallet instance ───────────────────────────────────────
// Reuse the same LMDB environment across FFI calls to prevent
// data loss between init_send and finalize.

use std::sync::OnceLock;
use std::collections::HashMap;

struct CachedWallet {
    wallet: Wallet,
    is_open: bool,
}

static WALLET_CACHE: OnceLock<std::sync::Mutex<HashMap<String, CachedWallet>>> = OnceLock::new();

/// Global scan progress (0–100), updated by the scan status channel.
static SCAN_PROGRESS: AtomicU8 = AtomicU8::new(0);

fn get_or_create_wallet(data_dir: &str, node_url: &str) -> Result<Wallet, String> {
    let cache = WALLET_CACHE.get_or_init(|| std::sync::Mutex::new(HashMap::new()));
    let mut guard = cache.lock().map_err(|e| format!("Cache lock error: {}", e))?;

    let key = format!("{}|{}", data_dir, node_url);

    if let Some(cached) = guard.get(&key) {
        return Ok(cached.wallet.clone());
    }

    let node_client = create_node_client(node_url);
    let wallet = instantiate_wallet(data_dir, node_client)?;
    guard.insert(key, CachedWallet {
        wallet: wallet.clone(),
        is_open: false,
    });
    Ok(wallet)
}

// ─── String helpers ────────────────────────────────────────────────

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

unsafe fn from_c_str<'a>(ptr: *const c_char) -> &'a str {
    if ptr.is_null() { return ""; }
    CStr::from_ptr(ptr).to_str().unwrap_or("")
}

fn error_json(msg: &str) -> *mut c_char {
    let escaped = msg.replace('\\', "\\\\").replace('"', "\\\"").replace('\n', " ");
    to_c_string(&format!("{{\"error\":\"{}\"}}", escaped))
}

fn success_json(data: &str) -> *mut c_char {
    to_c_string(data)
}

// ─── Wallet instantiation helper ───────────────────────────────────

fn create_node_client(node_url: &str) -> HTTPNodeClient {
    HTTPNodeClient::new(node_url, None).unwrap()
}

fn init_chain_type(network: &str) {
    let chain_type = if network == "mainnet" {
        ChainTypes::Mainnet
    } else {
        ChainTypes::Testnet
    };
    // Only set if not already set
    let _ = std::panic::catch_unwind(|| {
        global::set_local_chain_type(chain_type);
    });
}

fn instantiate_wallet(data_dir: &str, node_client: HTTPNodeClient) -> Result<Wallet, String> {
    let mut wallet = Box::new(
        DefaultWalletImpl::<'static, HTTPNodeClient>::new(node_client.clone())
            .map_err(|e| format!("Failed to create wallet instance: {}", e))?,
    ) as Box<
        dyn WalletInst<
            'static,
            DefaultLCProvider<HTTPNodeClient, ExtKeychain>,
            HTTPNodeClient,
            ExtKeychain,
        >,
    >;

    let lc = wallet.lc_provider().map_err(|e| format!("{}", e))?;
    lc.set_top_level_directory(data_dir)
        .map_err(|e| format!("{}", e))?;

    Ok(Arc::new(Mutex::new(wallet)))
}

fn open_wallet_impl(
    wallet: &Wallet,
    password: &str,
    data_dir: &str,
    node_url: &str,
) -> Result<Option<grin_util::secp::key::SecretKey>, String> {
    let cache = WALLET_CACHE.get_or_init(|| std::sync::Mutex::new(HashMap::new()));
    let key = format!("{}|{}", data_dir, node_url);
    {
        let guard = cache.lock().map_err(|e| format!("Cache lock error: {}", e))?;
        if let Some(cached) = guard.get(&key) {
            if cached.is_open {
                return Ok(None);
            }
        }
    }

    let mut w_lock = wallet.lock();
    let lc = w_lock.lc_provider().map_err(|e| format!("{}", e))?;
    let result = lc.open_wallet(None, ZeroingString::from(password), false, false)
        .map_err(|e| format!("{}", e))?;

    drop(w_lock);
    {
        let mut guard = cache.lock().map_err(|e| format!("Cache lock error: {}", e))?;
        if let Some(cached) = guard.get_mut(&key) {
            cached.is_open = true;
        }
    }

    Ok(result)
}

/// Explicitly close the wallet backend (flushes LMDB).
#[allow(dead_code)]
fn close_wallet_impl(wallet: &Wallet) {
    let mut w_lock = wallet.lock();
    if let Ok(lc) = w_lock.lc_provider() {
        let _ = lc.close_wallet(None::<&str>);
    }
}

// ─── Public FFI functions ──────────────────────────────────────────

#[no_mangle]
pub extern "C" fn grin_str_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { let _ = CString::from_raw(ptr); }
    }
}

#[no_mangle]
pub extern "C" fn grin_wallet_version() -> *mut c_char {
    to_c_string("{\"version\":\"0.1.0\",\"grin_wallet\":\"5.4.0-alpha.1\"}")
}

/// Create a new wallet. Returns JSON with mnemonic.
/// word_count: BIP39 mnemonic length (12, 15, 18, 21, or 24). Other values default to 24.
#[no_mangle]
pub extern "C" fn grin_wallet_create(
    data_dir: *const c_char,
    password: *const c_char,
    network: *const c_char,
    word_count: u16,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let network = unsafe { from_c_str(network) };

    let entropy_bytes: usize = match word_count {
        12 => 16,
        15 => 20,
        18 => 24,
        21 => 28,
        _ => 32, // 24 words
    };

    init_chain_type(network);

    let node_client = create_node_client("http://127.0.0.1:3413"); // placeholder, not needed for create
    let wallet = match instantiate_wallet(data_dir, node_client) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    // Create wallet config and wallet data
    {
        let mut w_lock = wallet.lock();
        let lc = match w_lock.lc_provider() {
            Ok(l) => l,
            Err(e) => return error_json(&format!("{}", e)),
        };

        let chain_type = if network == "mainnet" {
            ChainTypes::Mainnet
        } else {
            ChainTypes::Testnet
        };

        if let Err(e) = lc.create_config(&chain_type, WALLET_CONFIG_FILE_NAME, None, None, None) {
            return error_json(&format!("Failed to create config: {}", e));
        }

        if let Err(e) = lc.create_wallet(None, None, entropy_bytes, ZeroingString::from(password), false) {
            return error_json(&format!("Failed to create wallet: {}", e));
        }

        // Get the mnemonic
        match lc.get_mnemonic(None, ZeroingString::from(password)) {
            Ok(mnemonic) => {
                let json = format!(
                    "{{\"status\":\"ok\",\"mnemonic\":\"{}\"}}",
                    &*mnemonic
                );
                return success_json(&json);
            }
            Err(e) => return error_json(&format!("Failed to get mnemonic: {}", e)),
        }
    }
}

/// Restore wallet from mnemonic seed phrase.
#[no_mangle]
pub extern "C" fn grin_wallet_restore(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
    mnemonic: *const c_char,
    network: *const c_char,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let _node_url = unsafe { from_c_str(node_url) };
    let mnemonic = unsafe { from_c_str(mnemonic) };
    let network = unsafe { from_c_str(network) };

    init_chain_type(network);

    let node_client = create_node_client(_node_url);
    let wallet = match instantiate_wallet(data_dir, node_client) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    {
        let mut w_lock = wallet.lock();
        let lc = match w_lock.lc_provider() {
            Ok(l) => l,
            Err(e) => return error_json(&format!("{}", e)),
        };

        let chain_type = if network == "mainnet" {
            ChainTypes::Mainnet
        } else {
            ChainTypes::Testnet
        };

        if let Err(e) = lc.create_config(&chain_type, WALLET_CONFIG_FILE_NAME, None, None, None) {
            return error_json(&format!("Failed to create config: {}", e));
        }

        if let Err(e) = lc.create_wallet(
            None,
            Some(ZeroingString::from(mnemonic)),
            32,
            ZeroingString::from(password),
            false,
        ) {
            return error_json(&format!("Failed to restore wallet: {}", e));
        }
    }

    success_json("{\"status\":\"ok\",\"restored\":true}")
}

/// Open an existing wallet and verify password.
#[no_mangle]
pub extern "C" fn grin_wallet_open(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    match open_wallet_impl(&wallet, password, data_dir, node_url) {
        Ok(_) => {
            success_json("{\"status\":\"ok\"}")
        }
        Err(e) => error_json(&e),
    }
}

/// Check if a wallet exists at the given data directory.
#[no_mangle]
pub extern "C" fn grin_wallet_exists(
    data_dir: *const c_char,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };

    init_chain_type("testnet");

    let node_client = create_node_client("http://127.0.0.1:3413");
    let wallet = match instantiate_wallet(data_dir, node_client) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    let exists = {
        let mut w_lock = wallet.lock();
        match w_lock.lc_provider() {
            Ok(lc) => lc.wallet_exists(None).unwrap_or(false),
            Err(_) => false,
        }
    };

    success_json(&format!("{{\"exists\":{}}}", exists))
}

/// Get wallet balance info.
#[no_mangle]
pub extern "C" fn grin_wallet_balance(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
    minimum_confirmations: u64,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };

    let min_conf = if minimum_confirmations == 0 { 10 } else { minimum_confirmations };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    let mut owner_api = Owner::new(wallet.clone(), None);
    let result = match owner_api.retrieve_summary_info(None, true, min_conf) {
        Ok((validated, info)) => {
            let json = format!(
                "{{\"status\":\"ok\",\"validated\":{},\"total\":{},\"spendable\":{},\"immature\":{},\"locked\":{},\"awaiting_confirmation\":{},\"awaiting_finalization\":{}}}",
                validated,
                info.total,
                info.amount_currently_spendable,
                info.amount_immature,
                info.amount_locked,
                info.amount_awaiting_confirmation,
                info.amount_awaiting_finalization,
            );
            success_json(&json)
        }
        Err(e) => error_json(&format!("{}", e)),
    };
    result
}

/// Get transaction list.
#[no_mangle]
pub extern "C" fn grin_wallet_txs(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    let mut owner_api = Owner::new(wallet.clone(), None);
    let result = match owner_api.retrieve_txs(None, true, None, None, None) {
        Ok((validated, txs)) => {
            match serde_json::to_string(&txs) {
                Ok(txs_json) => {
                    let json = format!(
                        "{{\"status\":\"ok\",\"validated\":{},\"txs\":{}}}",
                        validated, txs_json
                    );
                    success_json(&json)
                }
                Err(e) => error_json(&format!("Serialization error: {}", e)),
            }
        }
        Err(e) => error_json(&format!("{}", e)),
    };
    result
}

/// Initiate a send transaction. Returns a slatepack string.
#[no_mangle]
pub extern "C" fn grin_wallet_send(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
    amount_nanogrin: u64,
    minimum_confirmations: u64,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };

    let min_conf = if minimum_confirmations == 0 { 10 } else { minimum_confirmations };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    let mut owner_api = Owner::new(wallet.clone(), None);

    let args = grin_wallet_libwallet::InitTxArgs {
        src_acct_name: None,
        amount: amount_nanogrin,
        minimum_confirmations: min_conf,
        max_outputs: 500,
        num_change_outputs: 1,
        selection_strategy_is_use_all: false,
        ..Default::default()
    };

    let result = match owner_api.init_send_tx(None, args) {
        Ok(slate) => {
            // Encode as slatepack
            let slatepack_args = SlatepackerArgs {
                sender: None,
                recipients: vec![],
                dec_key: None,
            };
            let slatepacker = Slatepacker::new(slatepack_args);
            match slatepacker.create_slatepack(&slate) {
                Ok(slatepack) => {
                    match slatepacker.armor_slatepack(&slatepack) {
                        Ok(armored) => {
                            let json = format!(
                                "{{\"status\":\"ok\",\"slatepack\":\"{}\"}}",
                                armored.replace('"', "\\\"").replace('\n', "\\n")
                            );
                            success_json(&json)
                        }
                        Err(e) => error_json(&format!("Failed to armor slatepack: {}", e)),
                    }
                }
                Err(e) => error_json(&format!("Failed to create slatepack: {}", e)),
            }
        }
        Err(e) => error_json(&format!("{}", e)),
    };
    result
}

/// Receive/sign a slatepack. Returns a response slatepack.
#[no_mangle]
pub extern "C" fn grin_wallet_receive(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
    slatepack_str: *const c_char,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };
    let slatepack_str = unsafe { from_c_str(slatepack_str) };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    // Decode incoming slatepack
    let slatepacker = Slatepacker::new(SlatepackerArgs {
        sender: None,
        recipients: vec![],
        dec_key: None,
    });

    let slate = match slatepacker.deser_slatepack(slatepack_str.as_bytes(), true) {
        Ok(sp) => match slatepacker.get_slate(&sp) {
            Ok(s) => s,
            Err(e) => return error_json(&format!("Failed to extract slate: {}", e)),
        },
        Err(e) => return error_json(&format!("Failed to decode slatepack: {}", e)),
    };

    let foreign_api = Foreign::new(wallet.clone(), None, None, false);

    // Use foreign API for receive
    let result = match foreign_api.receive_tx(&slate, None, None) {
        Ok(response_slate) => {
            let slatepack_args = SlatepackerArgs {
                sender: None,
                recipients: vec![],
                dec_key: None,
            };
            let response_packer = Slatepacker::new(slatepack_args);
            match response_packer.create_slatepack(&response_slate) {
                Ok(sp) => match response_packer.armor_slatepack(&sp) {
                    Ok(armored) => {
                        let json = format!(
                            "{{\"status\":\"ok\",\"slatepack\":\"{}\"}}",
                            armored.replace('"', "\\\"").replace('\n', "\\n")
                        );
                        success_json(&json)
                    }
                    Err(e) => error_json(&format!("Failed to armor response: {}", e)),
                },
                Err(e) => error_json(&format!("Failed to create response slatepack: {}", e)),
            }
        }
        Err(e) => error_json(&format!("{}", e)),
    };
    result
}

/// Finalise a transaction from a response slatepack.
#[no_mangle]
pub extern "C" fn grin_wallet_finalize(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
    response_slatepack: *const c_char,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };
    let response_slatepack = unsafe { from_c_str(response_slatepack) };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    // Decode response slatepack
    let slatepacker = Slatepacker::new(SlatepackerArgs {
        sender: None,
        recipients: vec![],
        dec_key: None,
    });

    let slate = match slatepacker.deser_slatepack(response_slatepack.as_bytes(), true) {
        Ok(sp) => match slatepacker.get_slate(&sp) {
            Ok(s) => s,
            Err(e) => return error_json(&format!("Failed to extract slate: {}", e)),
        },
        Err(e) => return error_json(&format!("Failed to decode slatepack: {}", e)),
    };

    let mut owner_api = Owner::new(wallet.clone(), None);

    // Lock outputs BEFORE finalize — this creates the tx log entry,
    // locks inputs, and saves change outputs to LMDB so that
    // repopulate_tx can find them during finalize.
    if let Err(e) = owner_api.tx_lock_outputs(None, &slate) {
        return error_json(&format!("Lock outputs failed: {:?}", e));
    }

    let result = match owner_api.finalize_tx(None, &slate) {
        Ok(finalized_slate) => {
            // Post to node
            match owner_api.post_tx(None, &finalized_slate, true) {
                Ok(_) => success_json("{\"status\":\"ok\",\"finalized\":true}"),
                Err(e) => error_json(&format!("Finalized but failed to post: {:?}", e)),
            }
        }
        Err(e) => error_json(&format!("Finalize failed: {:?}", e)),
    };
    result
}

/// Cancel a transaction by ID.
#[no_mangle]
pub extern "C" fn grin_wallet_cancel(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
    tx_id: u32,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    let mut owner_api = Owner::new(wallet.clone(), None);
    let result = match owner_api.cancel_tx(None, Some(tx_id), None) {
        Ok(_) => success_json("{\"status\":\"ok\",\"cancelled\":true}"),
        Err(e) => error_json(&format!("{}", e)),
    };
    result
}

/// Check node connectivity and get chain height.
#[no_mangle]
pub extern "C" fn grin_node_info(
    node_url: *const c_char,
) -> *mut c_char {
    let node_url = unsafe { from_c_str(node_url) };

    let node_client = create_node_client(node_url);
    match node_client.get_chain_tip() {
        Ok((height, hash)) => {
            let json = format!(
                "{{\"status\":\"ok\",\"height\":{},\"hash\":\"{}\"}}",
                height,
                hash
            );
            success_json(&json)
        }
        Err(e) => error_json(&format!("{}", e)),
    }
}

/// Get the wallet's slatepack address.
#[no_mangle]
pub extern "C" fn grin_wallet_address(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    let mut owner_api = Owner::new(wallet.clone(), None);
    let result = match owner_api.get_slatepack_address(None, 0) {
        Ok(address) => {
            let json = format!("{{\"status\":\"ok\",\"address\":\"{}\"}}", address);
            success_json(&json)
        }
        Err(e) => error_json(&format!("{}", e)),
    };
    result
}

/// Scan and repair wallet outputs against the chain.
/// start_height: block height to start scanning from. 0 defaults to 1 (genesis).
#[no_mangle]
pub extern "C" fn grin_wallet_scan(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
    start_height: u64,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };

    let height = if start_height == 0 { 1 } else { start_height };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    // Set up a status channel so we can track scan progress
    SCAN_PROGRESS.store(0, Ordering::SeqCst);
    let (tx, rx) = channel();

    // Spawn a thread to read status messages and update the global progress
    std::thread::spawn(move || {
        while let Ok(msg) = rx.recv() {
            if let StatusMessage::Scanning(_, pct) = msg {
                SCAN_PROGRESS.store(pct, Ordering::SeqCst);
            }
        }
    });

    let mut owner_api = Owner::new(wallet.clone(), Some(tx));
    let result = match owner_api.scan(None, Some(height), true) {
        Ok(_) => {
            SCAN_PROGRESS.store(100, Ordering::SeqCst);
            success_json("{\"status\":\"ok\",\"scanned\":true}")
        }
        Err(e) => error_json(&format!("Scan failed: {:?}", e)),
    };
    result
}

/// Retrieve the wallet's BIP39 mnemonic (recovery phrase).
#[no_mangle]
pub extern "C" fn grin_wallet_mnemonic(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    let mut w_lock = wallet.lock();
    let lc = match w_lock.lc_provider() {
        Ok(l) => l,
        Err(e) => return error_json(&format!("{}", e)),
    };

    match lc.get_mnemonic(None, ZeroingString::from(password)) {
        Ok(mnemonic) => {
            let json = format!("{{\"status\":\"ok\",\"mnemonic\":\"{}\"}}", &*mnemonic);
            success_json(&json)
        }
        Err(e) => error_json(&format!("Failed to get mnemonic: {}", e)),
    }
}

/// Get the current scan progress (0–100).
#[no_mangle]
pub extern "C" fn grin_wallet_scan_progress() -> u8 {
    SCAN_PROGRESS.load(Ordering::SeqCst)
}

/// Retrieve wallet outputs. Returns JSON array of outputs.
/// include_spent: if true, includes spent outputs; if false, only unspent/locked.
#[no_mangle]
pub extern "C" fn grin_wallet_outputs(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
    include_spent: bool,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    let owner_api = Owner::new(wallet.clone(), None);

    let result = match owner_api.retrieve_outputs(None, include_spent, true, None) {
        Ok((_updated, outputs)) => {
            let output_list: Vec<serde_json::Value> = outputs
                .iter()
                .map(|o| {
                    serde_json::json!({
                        "commit": o.output.commit.as_deref().unwrap_or(""),
                        "value": o.output.value,
                        "status": format!("{}", o.output.status),
                        "height": o.output.height,
                        "lock_height": o.output.lock_height,
                        "is_coinbase": o.output.is_coinbase,
                        "tx_log_entry": o.output.tx_log_entry,
                        "n_child": o.output.n_child,
                        "mmr_index": o.output.mmr_index,
                    })
                })
                .collect();
            let json_str = serde_json::to_string(&serde_json::json!({
                "status": "ok",
                "outputs": output_list
            }))
            .unwrap_or_else(|_| "{\"error\":\"JSON serialization failed\"}".to_string());
            to_c_string(&json_str)
        }
        Err(e) => error_json(&format!("Failed to retrieve outputs: {:?}", e)),
    };
    result
}

/// Issue an invoice (receiver-initiated). Returns a slatepack string for the sender.
#[no_mangle]
pub extern "C" fn grin_wallet_issue_invoice(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
    amount_nanogrin: u64,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    let mut owner_api = Owner::new(wallet.clone(), None);

    let args = IssueInvoiceTxArgs {
        amount: amount_nanogrin,
        ..Default::default()
    };

    let result = match owner_api.issue_invoice_tx(None, args) {
        Ok(slate) => {
            let slatepack_args = SlatepackerArgs {
                sender: None,
                recipients: vec![],
                dec_key: None,
            };
            let slatepacker = Slatepacker::new(slatepack_args);
            match slatepacker.create_slatepack(&slate) {
                Ok(slatepack) => {
                    match slatepacker.armor_slatepack(&slatepack) {
                        Ok(armored) => {
                            let json = format!(
                                "{{\"status\":\"ok\",\"slatepack\":\"{}\"}}",
                                armored.replace('"', "\\\"").replace('\n', "\\n")
                            );
                            success_json(&json)
                        }
                        Err(e) => error_json(&format!("Failed to armor slatepack: {}", e)),
                    }
                }
                Err(e) => error_json(&format!("Failed to create slatepack: {}", e)),
            }
        }
        Err(e) => error_json(&format!("{}", e)),
    };
    result
}

/// Process an invoice slatepack (sender pays invoice). Returns a response slatepack.
/// Locks outputs on the sender side.
#[no_mangle]
pub extern "C" fn grin_wallet_process_invoice(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
    invoice_slatepack: *const c_char,
    minimum_confirmations: u64,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };
    let invoice_slatepack = unsafe { from_c_str(invoice_slatepack) };

    let min_conf = if minimum_confirmations == 0 { 10 } else { minimum_confirmations };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    // Decode incoming invoice slatepack
    let slatepacker = Slatepacker::new(SlatepackerArgs {
        sender: None,
        recipients: vec![],
        dec_key: None,
    });

    let slate = match slatepacker.deser_slatepack(invoice_slatepack.as_bytes(), true) {
        Ok(sp) => match slatepacker.get_slate(&sp) {
            Ok(s) => s,
            Err(e) => return error_json(&format!("Failed to extract slate: {}", e)),
        },
        Err(e) => return error_json(&format!("Failed to decode slatepack: {}", e)),
    };

    let mut owner_api = Owner::new(wallet.clone(), None);

    let args = InitTxArgs {
        src_acct_name: None,
        amount: slate.amount,
        minimum_confirmations: min_conf,
        max_outputs: 500,
        num_change_outputs: 1,
        selection_strategy_is_use_all: false,
        ..Default::default()
    };

    let result = match owner_api.process_invoice_tx(None, &slate, args) {
        Ok(response_slate) => {
            // Lock outputs on the sender side
            if let Err(e) = owner_api.tx_lock_outputs(None, &response_slate) {
                return error_json(&format!("Lock outputs failed: {:?}", e));
            }

            let slatepack_args = SlatepackerArgs {
                sender: None,
                recipients: vec![],
                dec_key: None,
            };
            let response_packer = Slatepacker::new(slatepack_args);
            match response_packer.create_slatepack(&response_slate) {
                Ok(sp) => match response_packer.armor_slatepack(&sp) {
                    Ok(armored) => {
                        let json = format!(
                            "{{\"status\":\"ok\",\"slatepack\":\"{}\"}}",
                            armored.replace('"', "\\\"").replace('\n', "\\n")
                        );
                        success_json(&json)
                    }
                    Err(e) => error_json(&format!("Failed to armor response: {}", e)),
                },
                Err(e) => error_json(&format!("Failed to create response slatepack: {}", e)),
            }
        }
        Err(e) => error_json(&format!("{}", e)),
    };
    result
}

/// Finalise an invoice transaction (receiver finalizes). Does NOT lock outputs
/// (sender already locked them in process_invoice).
#[no_mangle]
pub extern "C" fn grin_wallet_finalize_invoice(
    data_dir: *const c_char,
    password: *const c_char,
    node_url: *const c_char,
    response_slatepack: *const c_char,
) -> *mut c_char {
    let data_dir = unsafe { from_c_str(data_dir) };
    let password = unsafe { from_c_str(password) };
    let node_url = unsafe { from_c_str(node_url) };
    let response_slatepack = unsafe { from_c_str(response_slatepack) };

    init_chain_type("testnet");

    let wallet = match get_or_create_wallet(data_dir, node_url) {
        Ok(w) => w,
        Err(e) => return error_json(&e),
    };

    if let Err(e) = open_wallet_impl(&wallet, password, data_dir, node_url) {
        return error_json(&e);
    }

    // Decode response slatepack
    let slatepacker = Slatepacker::new(SlatepackerArgs {
        sender: None,
        recipients: vec![],
        dec_key: None,
    });

    let slate = match slatepacker.deser_slatepack(response_slatepack.as_bytes(), true) {
        Ok(sp) => match slatepacker.get_slate(&sp) {
            Ok(s) => s,
            Err(e) => return error_json(&format!("Failed to extract slate: {}", e)),
        },
        Err(e) => return error_json(&format!("Failed to decode slatepack: {}", e)),
    };

    let mut owner_api = Owner::new(wallet.clone(), None);

    // NOTE: No tx_lock_outputs here — sender already locked in process_invoice
    let result = match owner_api.finalize_tx(None, &slate) {
        Ok(finalized_slate) => {
            match owner_api.post_tx(None, &finalized_slate, true) {
                Ok(_) => success_json("{\"status\":\"ok\",\"finalized\":true}"),
                Err(e) => error_json(&format!("Finalized but failed to post: {:?}", e)),
            }
        }
        Err(e) => error_json(&format!("Finalize failed: {:?}", e)),
    };
    result
}
