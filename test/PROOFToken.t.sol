// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PROOFToken} from "../src/PROOFToken.sol";

interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address sender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
}

/// @dev Local actors are test fixtures only; no deployment addresses are inferred from them.
contract PROOFTokenTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1e27;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    address private constant DISTRIBUTOR = address(0xD157);
    address private constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    PROOFToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new PROOFToken();
    }

    function test_LaunchMetadataAndEntireSupplyBelongToDeployer() public view {
        require(keccak256(bytes(token.name())) == keccak256("Proof Network"), "name");
        require(keccak256(bytes(token.symbol())) == keccak256("PROOF"), "symbol");
        require(token.decimals() == 18, "decimals");
        require(token.totalSupply() == SUPPLY, "supply");
        require(token.balanceOf(address(this)) == SUPPLY, "full deployer allocation");
        require(token.balanceOf(address(token)) == 0, "no token reserve");
    }

    function test_ConstructorEmitsOneMint() public {
        // The constructor is the sole mint path.
        vm.recordLogs();
        PROOFToken deployed = new PROOFToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 1 && logs[0].emitter == address(deployed), "exactly one mint event");
        require(logs[0].topics[0] == keccak256("Transfer(address,address,uint256)"), "transfer event");
        require(logs[0].topics[1] == bytes32(0), "mint source");
        require(logs[0].topics[2] == bytes32(uint256(uint160(address(this)))), "mint recipient");
        require(abi.decode(logs[0].data, (uint256)) == SUPPLY, "mint amount");
    }

    function test_FactoryDistributionClaimsAndPoolTransfersAreExact() public {
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY - swarm;
        require(token.transfer(DISTRIBUTOR, swarm), "swarm transfer");
        require(token.transfer(POOL_MANAGER, pool), "seed transfer");
        require(token.balanceOf(address(this)) == 0, "factory exhausted");
        require(token.balanceOf(DISTRIBUTOR) == swarm, "whole swarm share");
        require(token.balanceOf(POOL_MANAGER) == pool, "whole pool share");

        vm.prank(DISTRIBUTOR);
        require(token.transfer(ALICE, swarm), "claim transfer");
        require(token.balanceOf(ALICE) == swarm, "whole claim");
        require(token.balanceOf(DISTRIBUTOR) == 0, "claim clears distributor");

        // Exercise the token-facing legs of a buy/sell. No AMM pricing is simulated.
        vm.prank(POOL_MANAGER);
        require(token.transfer(BOB, 123e18), "pool pays trader");
        require(token.balanceOf(BOB) == 123e18, "whole buy");
        vm.prank(BOB);
        require(token.transfer(POOL_MANAGER, 123e18), "trader pays pool");
        require(token.balanceOf(BOB) == 0, "whole sell");
        require(token.balanceOf(POOL_MANAGER) == pool, "pool round trip");
        require(token.totalSupply() == SUPPLY, "supply conserved");
    }

    function test_TransferAndApprovalEvents() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 42);
        require(token.transfer(ALICE, 42), "transfer result");
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 19);
        require(token.approve(SPENDER, 19), "approve result");
    }

    function test_ZeroAndSelfTransfersConserveBalances() public {
        token.transfer(ALICE, 0);
        token.transfer(address(this), SUPPLY);
        require(token.balanceOf(address(this)) == SUPPLY, "self transfer");
        vm.prank(ALICE);
        require(token.transfer(BOB, 0), "empty zero transfer");
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, 0), "zero transferFrom");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(BOB) == 0, "no new tokens");
    }

    function test_EntireSupplyCanMoveWithoutLimits() public {
        token.transfer(ALICE, SUPPLY);
        require(token.balanceOf(address(this)) == 0, "sender emptied");
        vm.prank(ALICE);
        token.transfer(BOB, SUPPLY);
        require(token.balanceOf(BOB) == SUPPLY, "no limit or fee");
    }

    function test_TransferAboveBalanceRevertsWithoutFreezingHolder() public {
        token.transfer(ALICE, 100);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InsufficientBalance.selector, ALICE, 100, 101));
        vm.prank(ALICE);
        token.transfer(BOB, 101);
        require(token.balanceOf(ALICE) == 100 && token.balanceOf(BOB) == 0, "failed transfer preserves balances");
        require(token.totalSupply() == SUPPLY, "failed transfer preserves supply");

        vm.prank(ALICE);
        require(token.transfer(BOB, 100), "holder can still transfer");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(BOB) == 100, "whole balance delivered");
    }

    function test_ApprovalCanBeOverwrittenAndRevoked() public {
        token.approve(SPENDER, 100);
        token.approve(SPENDER, 7);
        require(token.allowance(address(this), SPENDER) == 7, "replace allowance");
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_ExactAllowanceIsConsumed() public {
        token.approve(SPENDER, SUPPLY);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, SUPPLY), "transferFrom");
        require(token.balanceOf(ALICE) == SUPPLY, "full delivery");
        require(token.allowance(address(this), SPENDER) == 0, "allowance exhausted");
    }

    function test_InfiniteAllowanceIsPreserved() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, SUPPLY);
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "infinite allowance");
    }

    function test_DelegatedSelfTransferConsumesOnlyAllowance() public {
        token.approve(SPENDER, 100);
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(this), 60);
        require(token.balanceOf(address(this)) == SUPPLY, "balance unchanged");
        require(token.allowance(address(this), SPENDER) == 40, "allowance consumed");
    }

    function test_InsufficientBalanceRevertsAtomically() public {
        token.approve(SPENDER, SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(PROOFToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, SUPPLY + 1);
        require(token.allowance(address(this), SPENDER) == SUPPLY + 1, "allowance rolled back");
        require(token.balanceOf(address(this)) == SUPPLY, "balance rolled back");
    }

    function test_InsufficientAllowanceCannotMoveTokens() public {
        token.transfer(ALICE, 100);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        require(token.balanceOf(ALICE) == 100, "deployer has no privilege");
    }

    function test_ZeroRecipientAndSpenderAreRejected() public {
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        token.approve(SPENDER, 5);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 5);
        require(token.allowance(address(this), SPENDER) == 5, "failed transfer preserves allowance");
        require(token.totalSupply() == SUPPLY, "no burn");
    }

    function test_AdminSelectorsAreAbsentForDeployerAndStrangers() public {
        token.transfer(ALICE, 100);
        bytes[10] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", ALICE, 1),
            abi.encodeWithSignature("mint(uint256)", 1),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("transferOwnership(address)", ALICE),
            abi.encodeWithSignature("upgradeTo(address)", ALICE),
            abi.encodeWithSignature("initialize(address)", ALICE),
            abi.encodeWithSignature("owner()")
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerOK,) = address(token).call(calls[i]);
            require(!deployerOK, "deployer admin call accepted");
            vm.prank(BOB);
            (bool strangerOK,) = address(token).call(calls[i]);
            require(!strangerOK, "stranger admin call accepted");
        }
        require(token.balanceOf(ALICE) == 100 && token.totalSupply() == SUPPLY, "no privileged mutation");
        vm.prank(ALICE);
        token.transfer(BOB, 100);
        require(token.balanceOf(BOB) == 100, "holder can still transfer");
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        require(runtime.length > 0 && runtime.length <= 24_576, "runtime size");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                require(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
            }
        }
    }

    function testFuzz_DelegatedRoundTrip(uint256 rawAmount, uint256 rawExtraAllowance) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        uint256 extraAllowance = rawExtraAllowance % (SUPPLY + 1);
        token.transfer(ALICE, amount);
        vm.prank(ALICE);
        token.approve(SPENDER, amount + extraAllowance);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        require(token.allowance(ALICE, SPENDER) == extraAllowance, "exact spending");
        require(token.balanceOf(ALICE) == 0 && token.balanceOf(BOB) == amount, "no fee");
        vm.prank(BOB);
        token.transfer(address(this), amount);
        require(token.balanceOf(address(this)) == SUPPLY, "round trip preserves value");
        require(token.totalSupply() == SUPPLY, "fixed supply");
    }

    function testFuzz_SequencesConserveSupply(bytes32 seed) public {
        address[4] memory holders = [address(this), ALICE, BOB, POOL_MANAGER];
        for (uint256 i; i < 32; ++i) {
            seed = keccak256(abi.encode(seed, i));
            address from = holders[uint256(seed) % holders.length];
            address to = holders[(uint256(seed) >> 8) % holders.length];
            uint256 amount = (uint256(seed) >> 16) % (token.balanceOf(from) + 1);
            if (i % 2 == 0) {
                vm.prank(from);
                token.transfer(to, amount);
            } else {
                vm.prank(from);
                token.approve(SPENDER, amount);
                vm.prank(SPENDER);
                token.transferFrom(from, to, amount);
                require(token.allowance(from, SPENDER) == 0, "allowance exhausted");
            }
            uint256 sum;
            for (uint256 j; j < holders.length; ++j) {
                sum += token.balanceOf(holders[j]);
            }
            require(sum == SUPPLY && token.totalSupply() == SUPPLY, "conservation after each operation");
        }
    }
}
