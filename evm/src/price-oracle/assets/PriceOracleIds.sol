// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.25;

// ----------- Dispatcher Ids -----------

uint8 constant DISPATCHER_PROTOCOL_VERSION0 = 0;

// Execute commands

uint8 constant PRICES_ID = 0x00;
uint8 constant UPDATE_ASSISTANT_ID = 0x01;

// Query commands

uint8 constant PRICES_QUERIES_ID = 0x80;
uint8 constant ASSISTANT_ID = 0x81;

// ----------- Prices Ids ---------------

// Execute commands

uint8 constant FEE_PARAMS_ID = 0x00;
uint8 constant GAS_PRICE_ID = 0x01;
uint8 constant PRICE_PER_BYTE_ID = 0x02;
uint8 constant GAS_TOKEN_PRICE_ID = 0x03;
uint8 constant ACCOUNT_OVERHEAD_ID = 0x04;
uint8 constant ACCOUNT_SIZE_COST_ID = 0x05;

// Query commands

uint8 constant EVM_TX_QUOTE_ID = 0x80;
uint8 constant SOLANA_TX_QUOTE_ID = 0x81;

uint8 constant QUERY_FEE_PARAMS_ID = 0x90;
uint8 constant CHAIN_ID_ID = 0x91;
