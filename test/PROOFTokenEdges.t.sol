// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PROOFToken} from "../src/PROOFToken.sol";
import {TokenTestBase} from "./helpers/TokenTestBase.sol";

contract ConstructorCaller {
    function deploy() external returns (PROOFToken) {
        return new PROOFToken();
    }
}

/// @dev Adds adversarial cases to the original contributor's unit tests.
contract PROOFTokenEdgesTest is TokenTestBase {
    PROOFToken private token;

    function setUp() public {
        token = new PROOFToken();
    }

    function test_ConstructorMintsToCallingContractNotTransactionOrigin() public {
        ConstructorCaller factory = new ConstructorCaller();
        vm.prank(ALICE, BOB);
        PROOFToken deployed = factory.deploy();
        eq(deployed.balanceOf(address(factory)), SUPPLY, "factory must receive all supply");
        eq(deployed.balanceOf(ALICE), 0, "external caller receives no allocation");
        eq(deployed.balanceOf(BOB), 0, "tx.origin receives no allocation");
        eq(deployed.balanceOf(DISTRIBUTOR), 0, "token must not pre-distribute the swarm allocation");
        eq(deployed.balanceOf(POOL_MANAGER), 0, "token must not pre-seed the pool");
        eq(deployed.balanceOf(REMAINDER_TO), 0, "token must not pre-distribute the remainder");
        eq(deployed.totalSupply(), SUPPLY, "fixed launch supply");
    }

    function test_ZeroSenderAndApproverAreRejected() public {
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(SPENDER, 0);
        // A zero-value spend passes the allowance check and reaches the sender check.
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InvalidSender.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 0);
        eq(token.balanceOf(address(0)), 0, "zero address cannot acquire supply");
    }

    function test_ZeroApprovalAndTransferFromStillEmitEvents() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 0);
        require(token.approve(SPENDER, 0), "zero approval returns true");
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, 0), "zero spend returns true");
        eq(token.allowance(ALICE, SPENDER), 0, "zero spend creates no allowance");
    }

    function test_OwnerAlsoNeedsAllowanceForTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        token.approve(address(this), 1);
        require(token.transferFrom(address(this), ALICE, 1), "explicit self approval works");
        eq(token.allowance(address(this), address(this)), 0, "self approval is consumed");
    }

    function test_MaxUintTransferAndSelfTransferCannotWrapBalances() public {
        bytes memory err = abi.encodeWithSelector(
            PROOFToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(err);
        token.transfer(ALICE, type(uint256).max);
        vm.expectRevert(err);
        token.transfer(address(this), type(uint256).max);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(err);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        eq(token.balanceOf(address(this)), SUPPLY, "overflow attempts preserve holder");
        eq(token.balanceOf(ALICE), 0, "overflow attempts cannot mint");
        eq(token.allowance(address(this), SPENDER), type(uint256).max, "failed spend preserves infinite allowance");
    }

    function test_InfiniteApprovalSurvivesRepeatedSpendsButCanBeRevoked() public {
        token.approve(SPENDER, type(uint256).max);
        for (uint256 i; i < 3; ++i) {
            vm.prank(SPENDER);
            require(token.transferFrom(address(this), ALICE, 1), "repeated spend");
            eq(token.allowance(address(this), SPENDER), type(uint256).max, "infinite allowance stays infinite");
        }
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        eq(token.balanceOf(ALICE), 3, "revoked allowance cannot spend again");
    }

    function test_AllowanceIsScopedToBothHolderAndSpender() public {
        token.transfer(ALICE, 100);
        token.approve(SPENDER, 100);
        vm.prank(ALICE);
        token.approve(BOB, 100);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, SPENDER, 1);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        eq(token.allowance(address(this), SPENDER), 100, "other holder's approval intact");
        eq(token.allowance(ALICE, BOB), 100, "other spender's approval intact");
    }

    function testFuzz_InsufficientAllowanceIsAtomic(uint256 rawBalance, uint256 rawAllowed) public {
        uint256 balance = 1 + rawBalance % SUPPLY;
        uint256 allowed = rawAllowed % balance;
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(PROOFToken.ERC20InsufficientAllowance.selector, SPENDER, allowed, allowed + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, allowed + 1);
        eq(token.allowance(ALICE, SPENDER), allowed, "revert preserves approval");
        eq(token.balanceOf(ALICE), balance, "revert preserves sender");
        eq(token.balanceOf(BOB), 0, "revert preserves recipient");
        eq(token.totalSupply(), SUPPLY, "revert preserves supply");
    }

    function testFuzz_OverdrawRollsBackFiniteAllowance(uint256 rawBalance, uint256 rawExtra) public {
        uint256 balance = rawBalance % (SUPPLY + 1);
        uint256 amount = balance + 1 + rawExtra % SUPPLY;
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, amount);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        eq(token.allowance(ALICE, SPENDER), amount, "allowance debit must roll back");
        eq(token.balanceOf(ALICE), balance, "balance intact");
        eq(token.balanceOf(BOB), 0, "recipient intact");
    }

    function testFuzz_ZeroRecipientRollsBackEveryAllowance(uint256 rawAmount, uint256 approval) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        if (approval < amount) approval = amount;
        token.approve(SPENDER, approval);
        vm.expectRevert(abi.encodeWithSelector(PROOFToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), amount);
        eq(token.allowance(address(this), SPENDER), approval, "invalid recipient preserves approval");
        eq(token.balanceOf(address(this)), SUPPLY, "invalid recipient preserves balance");
        eq(token.balanceOf(address(0)), 0, "cannot burn through zero recipient");
    }

    function testFuzz_SelfTransfersStillRequireBalance(uint256 rawBalance) public {
        uint256 balance = rawBalance % (SUPPLY + 1);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, balance + 1);
        vm.expectRevert(
            abi.encodeWithSelector(PROOFToken.ERC20InsufficientBalance.selector, ALICE, balance, balance + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, balance + 1);
        eq(token.allowance(ALICE, SPENDER), balance + 1, "failed self transfer cannot consume allowance");
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, ALICE, balance), "valid delegated self transfer");
        eq(token.balanceOf(ALICE), balance, "self transfer neither mints nor burns");
        eq(token.allowance(ALICE, SPENDER), 1, "successful self transfer consumes allowance");
    }

    function test_NoHiddenAdministrativeOrBurnSurface() public {
        token.transfer(ALICE, 100);
        bytes[18] memory calls = [
            abi.encodeWithSignature("mint()"),
            abi.encodeWithSignature("issue(uint256)", 1),
            abi.encodeWithSignature("setOwner(address)", BOB),
            abi.encodeWithSignature("renounceOwnership()"),
            abi.encodeWithSignature("setMinter(address)", BOB),
            abi.encodeWithSignature("unpause()"),
            abi.encodeWithSignature("setFee(uint256)", 100),
            abi.encodeWithSignature("setTax(uint256)", 100),
            abi.encodeWithSignature("setMaxTransfer(uint256)", 1),
            abi.encodeWithSignature("freeze(address)", ALICE),
            abi.encodeWithSignature("setBlacklist(address,bool)", ALICE, true),
            abi.encodeWithSignature("seize(address)", ALICE),
            abi.encodeWithSignature("disableTransfers()"),
            abi.encodeWithSignature("setTransfersEnabled(bool)", false),
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", BOB, bytes("")),
            abi.encodeWithSignature("initialize()"),
            abi.encodeWithSignature("burn(address,uint256)", ALICE, 1),
            abi.encodeWithSignature("grantRole(bytes32,address)", bytes32(0), BOB)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(token).call(calls[i]);
            require(!ok, "deployer cannot administer token");
            vm.prank(BOB);
            (ok,) = address(token).call(calls[i]);
            require(!ok, "stranger cannot administer token");
        }
        eq(token.balanceOf(ALICE), 100, "admin attempts cannot seize or burn");
        vm.prank(ALICE);
        require(token.transfer(BOB, 100), "admin attempts cannot freeze");
        eq(token.balanceOf(BOB), 100, "no fee or limit introduced");
        eq(token.totalSupply(), SUPPLY, "supply fixed after admin attempts");
    }

    function test_NoFallbackReceiveOrPayableTokenFunction() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call("");
        require(!ok, "no fallback");
        (ok,) = address(token).call{value: 1}("");
        require(!ok, "no receive");
        (ok,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (ALICE, 1)));
        require(!ok, "ERC20 transfer rejects ETH");
        eq(address(token).balance, 0, "failed calls retain no ETH");
        eq(token.balanceOf(ALICE), 0, "payable call must not transfer tokens");
    }
}
