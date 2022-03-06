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
pragma solidity ^0.7.0;

import "./MerkleTreeWithHistory.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol';

interface IVerifier {
  function verifyProof(bytes memory _proof, uint256[6] memory _input) external returns (bool);
}

abstract contract Tornado is ReentrancyGuard, ERC721{
  IVerifier public immutable verifier;
  uint256 public denomination;

  mapping(bytes32 => bool) public nullifierHashes;
  // we store all commitments just to prevent accidental deposits with the same commitment
  mapping(bytes32 => bool) public deposit_commitments;
  mapping(bytes32 => bool) public purchase_commitments;

  event Deposit(bytes32 indexed commitment, uint32 leafIndex, uint256 timestamp, uint256 _tokenID);
  event Purchase(bytes32 indexed commitment, uint32 leafIndex, uint256 timestamp);
  event Withdrawal(address to, bytes32 nullifierHash, uint256 _tokenID);

  // Define the phases
  enum Phase{SELLER, BUYER, SELLER_PAYMENT, BUYER_WITHDRAWAL_REFUND}


  // Additional parameters
  uint256 public start_range;
  uint256 public end_range;
  uint256 public number_of_sales;
  Phase public current_phase;
  uint256 public current_deposits;
  uint256 public current_purchases;
  uint256 public current_NFT_withdraws;
  uint256 public current_refund_withdraws;
  uint256 public random_index;
  uint256[] public token_IDs;
  MerkleTreeWithHistory public purchase_merkle_tree;
  MerkleTreeWithHistory public deposit_merkle_tree;

  /**
    @dev The constructor
    @param _verifier the address of SNARK verifier for this contract
    @param _hasher the address of MiMC hash contract
    @param _denomination transfer amount for each deposit
    @param _merkleTreeHeight the height of deposits' Merkle Tree
  */
  constructor(
    IVerifier _verifier,
    IHasher _hasher,
    uint256 _denomination,
    uint32 _merkleTreeHeight,
    uint256 _start_range,
    uint256 _end_range,
    uint256 _number_of_sales) {
    require(_denomination > 0, "denomination should be greater than 0");
    require(_start_range > 0, "start range should be greater than 0");
    require(_end_range > 0, "end range should be greater than 0");
    require(_number_of_sales > 0, "number of sales should be greater than 0");
    verifier = _verifier;
    denomination = _denomination;
    start_range = _start_range;
    end_range = _end_range;
    number_of_sales = _number_of_sales;
    current_phase = Phase.SELLER;
    current_deposits = 0;
    current_purchases = 0;
    current_NFT_withdraws = 0;
    current_refund_withdraws = 0;
    random_index = 0;
    token_IDs = new uint256[](_number_of_sales);

    purchase_merkle_tree = new MerkleTreeWithHistory(_merkleTreeHeight, _hasher);
    deposit_merkle_tree = new MerkleTreeWithHistory(_merkleTreeHeight, _hasher);
  }



  function get_random_number(uint256 random_index, uint256 s, uint256 e) public view returns (uint256) {
    uint256 pi = 14159265358979323846
    uint256 random_looping = pi[random_index % 20]
    uint256 random_number = 0
    for (uint256 i = 0; i < random_looping; i++) {
      random_number = random_number + pi[random_index + i] * 10**i
    }
    random_number = random_number % (e-s) + s
    random_index = random_index + 1
    return random_number
  }

  /**
    @dev Deposit funds into the contract. The caller must send (for ETH) or approve (for ERC20) value equal to or `denomination` of this instance.
    @param _commitment the note commitment, which is PedersenHash(nullifier + secret)
  */

  function deposit(bytes32 _commitment, uint256 _tokenID) external nonReentrant {
    require(!deposit_commitments[_commitment], "The commitment has been submitted");
    require(current_phase == Phase.SELLER, "Cannot deposit outside of seller phase");
    require(current_deposits <= number_of_sales, "No more deposits are needed");

    uint32 insertedIndex = deposit_merkle_tree.insert(_commitment);
    deposit_commitments[_commitment] = true;

    _processDeposit(_tokenID);

    emit Deposit(_commitment, insertedIndex, block.timestamp, _tokenID);
  }

  /** @dev this function is defined in a child contract */
  function _processDeposit(uint256 _tokenID) internal virtual;

  /**
    @dev Withdraw a deposit from the contract. `proof` is a zkSNARK proof data, and input is an array of circuit public inputs
    `input` array consists of:
      - merkle root of all deposits in the contract
      - hash of unique deposit nullifier to prevent double spends
      - the recipient of funds
      - optional fee that goes to the transaction sender (usually a relay)
  */
  function purchase(bytes32 _commitment, uint256 _tokenID) external payable nonReentrant {
    require(!purchase_commitments[_commitment], "The commitment has been submitted");
    require(current_phase == Phase.BUYER, "Cannot deposit outside of buyer phase");
    require(current_purchases <= number_of_sales, "No more purchases are needed");

    uint32 insertedIndex = purchase_merkle_tree.insert(_commitment);
    purchase_commitments[_commitment] = true;

    _processPurchase();
    emit Purchase(_commitment, insertedIndex, block.timestamp);
  }

  /** @dev this function is defined in a child contract */
  function _processPurchase() internal virtual;

  function withdrawNFT(
    bytes calldata _proof,
    bytes32 _root,
    bytes32 _withdraw_NFT_nullifierHash
    address payable _recipient
  ) external payable nonReentrant {


    require(!withdraw_NFT_nullifierHashes[_withdraw_NFT_nullifierHash], "The reciept has been already spent");
    require(isKnownRoot(_root), "Cannot find your merkle root"); // Make sure to use a recent one
    uint256 _relayer = 0;
    uint256 _fee = 0;
    uint256 _refund = 0;
    require(
      verifier.verifyProof(
        _proof,
        [uint256(_root), uint256(_nullifierHash), uint256(_recipient), uint256(_relayer), _fee, _refund]
      ),
      "Invalid withdraw proof"
    );

    uint256 rand = getRandomNumber();
    _token = token_IDs[rand];
    while(!NFT_tokens[_token]) {
      rand = rand + 1;
      if (rand == _number_of_sales) {
        rand = 0;
      }
      _token = token_IDs[rand];
    }

    _transfer(address(this), _recipient, _token);

    nullifierHashes[_nullifierHash] = true;
    _processWithdraw(_recipient, _token);
    emit Withdrawal(_recipient, _nullifierHash, _token);
  }

  /** @dev this function is defined in a child contract */
  function _processWithdraw(
    address payable _recipient,
    address payable _relayer,
    uint256 _fee,
    uint256 _refund
  ) internal virtual;

  /** @dev whether a note is already spent */
  function isSpent(bytes32 _nullifierHash) public view returns (bool) {
    return nullifierHashes[_nullifierHash];
  }

  /** @dev whether an array of notes is already spent */
  function isSpentArray(bytes32[] calldata _nullifierHashes) external view returns (bool[] memory spent) {
    spent = new bool[](_nullifierHashes.length);
    for (uint256 i = 0; i < _nullifierHashes.length; i++) {
      if (isSpent(_nullifierHashes[i])) {
        spent[i] = true;
      }
    }
  }
}
