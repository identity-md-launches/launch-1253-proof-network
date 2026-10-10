// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Only the Foundry cheatcodes used by this suite. No external test library or remapping is needed.
interface TokenTestVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address sender) external;
    function prank(address sender, address origin) external;
    function expectRevert(bytes calldata data) external;
    function expectRevert(bytes4 selector) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function etch(address target, bytes calldata code) external;
    function deal(address target, uint256 amount) external;
    function chainId(uint256 chain) external;
}

abstract contract TokenTestBase {
    TokenTestVm internal constant vm = TokenTestVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant SUPPLY = 1e27;
    address internal constant ALICE = address(uint160(uint256(keccak256("PROOF test alice"))));
    address internal constant BOB = address(uint160(uint256(keccak256("PROOF test bob"))));
    address internal constant SPENDER = address(uint160(uint256(keccak256("PROOF test spender"))));
    address internal constant DISTRIBUTOR = address(uint160(uint256(keccak256("PROOF test distributor"))));
    address internal constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant PAIR = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    address internal constant REMAINDER_TO = 0x000000000000000000000000000000000000dEaD;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function eq(uint256 actual, uint256 expected, string memory why) internal pure {
        require(actual == expected, why);
    }

    function eqBytes(bytes memory actual, bytes memory expected, string memory why) internal pure {
        require(keccak256(actual) == keccak256(expected), why);
    }
}
