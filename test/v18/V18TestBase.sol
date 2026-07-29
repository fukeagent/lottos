// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/RobinhoodToken.sol";
import "../../contracts/LotteryEngine.sol";

contract V18TestBase is Test {
    RobinhoodToken token;
    LotteryEngine engine;

    address owner = address(this);
    address devFeeReceiver = address(0x3333);
    address user1 = address(0x1111);
    address user2 = address(0x2222);
    address user3 = address(0x3333_3333);

    function setUp() public virtual {
        token = new RobinhoodToken();
        engine = new LotteryEngine(address(token), devFeeReceiver, 100 ether);
        token.setLotteryEngine(address(engine));

        token.setExemptions(owner, true, true, true);
        token.setExemptions(user1, true, false, false);
        token.setExemptions(user2, true, false, false);
        token.setExemptions(user3, true, false, false);
    }

    receive() external payable {}
}
