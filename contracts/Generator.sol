// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract Generator {
    uint current_nullifier = 0;
    // secret = 0, nullifier = 1, 2, 3
    bytes32[3] public sample_commitment = [bytes32(0xfd2da5d7e1cf33470f8f6dd6efa46ebb302545bf2dbdf935de96df0d5ace371e),
    bytes32(0x0045e23b5d865b3878912031aa94983ce56740eb737b7efcfe012d1093b060b4),
    bytes32(0x2d6f99ced46c13a3394a2b392dea8f320f039ce8b68bbf976a0656838d9558f4)];

}
