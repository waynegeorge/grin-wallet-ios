#ifndef GRIN_WALLET_FFI_H
#define GRIN_WALLET_FFI_H

#include <stdbool.h>
#include <stdint.h>

/// Free a string returned by any grin_* function.
void grin_str_free(char *ptr);

/// Get library version. Returns JSON string.
char *grin_wallet_version(void);

/// Check if a wallet exists at the given data directory.
char *grin_wallet_exists(const char *data_dir);

/// Create a new wallet. Returns JSON with mnemonic.
/// word_count: BIP39 mnemonic length (12, 15, 18, 21, or 24). Other values default to 24.
char *grin_wallet_create(const char *data_dir, const char *password, const char *network, uint16_t word_count);

/// Open an existing wallet. Returns JSON with status.
char *grin_wallet_open(const char *data_dir, const char *password, const char *node_url);

/// Get wallet balance. Returns JSON with balance info (amounts in nanogrin).
/// minimum_confirmations: outputs need this many confirmations to count as spendable. 0 defaults to 10.
char *grin_wallet_balance(const char *data_dir, const char *password, const char *node_url, uint64_t minimum_confirmations);

/// Get transaction list. Returns JSON array.
char *grin_wallet_txs(const char *data_dir, const char *password, const char *node_url);

/// Initiate a send. Returns JSON with slatepack string.
/// minimum_confirmations: outputs need this many confirmations to be selectable. 0 defaults to 10.
char *grin_wallet_send(const char *data_dir, const char *password, const char *node_url, uint64_t amount_nanogrin, uint64_t minimum_confirmations);

/// Receive/sign a slatepack. Returns JSON with response slatepack.
char *grin_wallet_receive(const char *data_dir, const char *password, const char *node_url, const char *slatepack);

/// Finalise a transaction. Returns JSON with result.
char *grin_wallet_finalize(const char *data_dir, const char *password, const char *node_url, const char *response_slatepack);

/// Cancel a transaction by ID. Returns JSON.
char *grin_wallet_cancel(const char *data_dir, const char *password, const char *node_url, uint32_t tx_id);

/// Restore wallet from mnemonic. Returns JSON.
char *grin_wallet_restore(const char *data_dir, const char *password, const char *node_url, const char *mnemonic, const char *network);

/// Check node info. Returns JSON with height and sync status.
char *grin_node_info(const char *node_url);

/// Get wallet's slatepack address.
char *grin_wallet_address(const char *data_dir, const char *password, const char *node_url);

/// Scan and repair wallet outputs against the chain.
/// start_height: block height to start scanning from. 0 defaults to 1 (genesis).
char *grin_wallet_scan(const char *data_dir, const char *password, const char *node_url, uint64_t start_height);

/// Retrieve the wallet's BIP39 mnemonic (recovery phrase).
char *grin_wallet_mnemonic(const char *data_dir, const char *password, const char *node_url);

/// Get the current scan progress (0–100).
uint8_t grin_wallet_scan_progress(void);

/// Retrieve wallet outputs. Returns JSON array.
/// include_spent: if true, includes spent outputs; if false, only unspent/locked.
char *grin_wallet_outputs(const char *data_dir, const char *password, const char *node_url, bool include_spent);

/// Issue an invoice (receiver-initiated). Returns JSON with slatepack string.
char *grin_wallet_issue_invoice(const char *data_dir, const char *password, const char *node_url, uint64_t amount_nanogrin);

/// Process an invoice slatepack (sender pays invoice). Returns JSON with response slatepack.
/// Locks outputs on the sender side.
/// minimum_confirmations: outputs need this many confirmations to be selectable. 0 defaults to 10.
char *grin_wallet_process_invoice(const char *data_dir, const char *password, const char *node_url, const char *invoice_slatepack, uint64_t minimum_confirmations);

/// Finalise an invoice transaction (receiver finalizes). Does NOT lock outputs.
char *grin_wallet_finalize_invoice(const char *data_dir, const char *password, const char *node_url, const char *response_slatepack);

#endif /* GRIN_WALLET_FFI_H */
