// https://tornado.cash
/*
 * d888888P                                           dP              a88888b.                   dP
 *    88                                              88             d8'   `88                   88
 *    88    .d8888b. 88d888b. 88d888b. .d8888b. .d888b88 .d8888b.    88        .d8888b. .d8888b. 88d888b.
 *    88    88'  `88 88'  `88 88'  `88 88'  `88 88'  `88 88'  `88    88        88'  `88 Y8ooooo. 88'  `88
 *    88    88.  .88 88       88    88 88.  .88 88.  .88 88.  .88 dP Y8.   .88 88.  .88       88 88    88
 *    dP    `88888P' dP       dP    dP `88888P8 `88888P8 `88888P' 88  Y88888P' `88888P8 `88888P' dP    dP
 * ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Tornado.sol";

contract ETHTornado is Tornado {
  constructor(
    IVerifier _verifier,
    IHasher _hasher,
    uint256 _denomination,
    uint32 _merkleTreeHeight,
    uint256 _start_range,
    uint256 _end_range,
    uint256 _number_of_sales
  ) Tornado(_verifier, _hasher, _denomination, _merkleTreeHeight,
    _start_range, _end_range, _number_of_sales) {}

  function _processDeposit(uint256 _tokenID, ERC721 _contractAddress) internal override {
    // require(msg.value == denomination, "Please send `mixDenomination` ETH along with transaction");

    _contractAddress.approve(address(this), _tokenID);
    // transfer NFT to this smart contract
    _contractAddress.transferFrom(msg.sender, address(this), _tokenID);

    // add tokenID to array and update current deposits count
    token_IDs[current_deposits] = _tokenID;
    current_deposits = current_deposits + 1;

    if (current_deposits == number_of_sales) {
      current_phase = Phase.BUYER;
    }

  }

  function _processPurchase() internal override {
    require(current_phase == Phase.BUYER);
    require(msg.value == end_range, "Please send the maximum ETH amount along with transaction");
    sale_amounts[current_purchases] = get_random_number(start_range, end_range);
    current_purchases = current_purchases + 1;

    if (current_purchases == number_of_sales) {
      current_phase = Phase.SELLER_PAYMENT;
    }
  }

  function _processPayment(
  address payable _recipient,
  address payable _relayer,
  uint256 _fee,
  uint256 _refund,
  uint256 random_sale_amount
) internal override {
  // sanity checks
  require(msg.value == 0, "Message value is supposed to be zero for ETH instance");
  require(_refund == 0, "Refund value is supposed to be zero for ETH instance");

  (bool success, ) = _recipient.call{ value: random_sale_amount - _fee }("");
  require(success, "payment to _recipient did not go thru");
  if (_fee > 0) {
    (success, ) = _relayer.call{ value: _fee }("");
    require(success, "payment to _relayer did not go thru");
  }

  current_payments = current_payments + 1;

  if (current_purchases == number_of_sales) {
    current_phase = Phase.BUYER_WITHDRAWAL_REFUND;
  }
}

  function _processWithdrawNFT(
    address payable _recipient,
    uint256 _tokenID,
    ERC721 _contractAddress
  ) internal override {
    // sanity checks
    require(msg.value == 0, "Message value is supposed to be zero for ETH instance");

    _contractAddress.approve(address(this), _tokenID);

    _contractAddress.transferFrom(address(this), _recipient, _tokenID);

    current_NFT_withdraws = current_NFT_withdraws + 1;

    if (current_NFT_withdraws == number_of_sales && current_refund_withdraws == number_of_sales) {
      current_phase = Phase.SELLER;
    }


  }

  function _processWithdrawRefund(
  address payable _recipient,
  address payable _relayer,
  uint256 _fee,
  uint256 _refund,
  uint256 random_sale_amount
) internal override {
  // sanity checks
  require(msg.value == 0, "Message value is supposed to be zero for ETH instance");
  require(_refund == 0, "Refund value is supposed to be zero for ETH instance");

  (bool success, ) = _recipient.call{ value: end_range - random_sale_amount - _fee }("");
  require(success, "payment to _recipient did not go thru");
  if (_fee > 0) {
    (success, ) = _relayer.call{ value: _fee }("");
    require(success, "payment to _relayer did not go thru");
  }

  current_refund_withdraws = current_refund_withdraws + 1;

  if (current_NFT_withdraws == number_of_sales && current_refund_withdraws == number_of_sales) {
    current_phase = Phase.SELLER;
  }
}
}
