// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A Lottery Smart Contract
 * @author w3rc
 * @notice This contrat creates a simple lottery system
 * @dev Implements Chainlink VRFv2
 */
contract Lottery is VRFConsumerBaseV2 {
    error Lottery__PleaseSendMoreEth();
    error Lottery__TransferCashToWinnerFailed();
    error Lottery__LotteryClosed();
    error Lottery__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numberOfPlayers,
        uint256 lotteryState
    );

    enum LotteryState {
        OPEN,
        CLOSED
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUMBER_OF_WORDS = 1;

    uint256 private immutable i_entryFee;
    // @dev Duration of lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gaslane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimestamp;
    address private s_recentWinner;
    LotteryState private s_lotteryState;

    event EnteredLottery(address indexed player);
    event PickedWinner(address indexed winner);

    constructor(
        uint256 entryFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entryFee = entryFee;
        i_interval = interval;
        s_lastTimestamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gaslane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lotteryState = LotteryState.OPEN;
    }

    function enterLottery() external payable {
        if (msg.value < i_entryFee) {
            revert Lottery__PleaseSendMoreEth();
        }
        if (s_lotteryState != LotteryState.OPEN) {
            revert Lottery__LotteryClosed();
        }
        s_players.push(payable(msg.sender));
        emit EnteredLottery(msg.sender);
    }

    /**
     * @dev This function is called by Chainlink to check if upkeep should be called
     * Conditions:
     * 1. Time interval has passed for lottery
     * 2. Lottery is OPEN
     * 3. Contract has ETH
     * 4. Subscription is funded with LINK
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasCome = (block.timestamp - s_lastTimestamp) >= i_interval;
        bool isOpen = LotteryState.OPEN == s_lotteryState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasCome && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "0x00");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Lottery__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_lotteryState)
            );
        }
        s_lotteryState = LotteryState.CLOSED;
        i_vrfCoordinator.requestRandomWords(
            i_gaslane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUMBER_OF_WORDS
        );
    }

    function fulfillRandomWords(
        uint256 /* _requestId */,
        uint256[] memory _randomWords
    ) internal override {
        uint256 indexOfWinner = _randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;

        s_players = new address payable[](0);
        s_lastTimestamp = block.timestamp;
        emit PickedWinner(winner);

        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Lottery__TransferCashToWinnerFailed();
        }
    }

    function getEntryFee() external view returns (uint256) {
        return i_entryFee;
    }
}
