// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

/**
 * @title A Lottery Smart Contract
 * @author w3rc
 * @notice This contrat creates a simple lottery system
 * @dev Implements Chainlink VRFv2
 */
contract Lottery is VRFConsumerBaseV2, AutomationCompatibleInterface {
    error Lottery__PleaseSendMoreEth();
    error Lottery__TransferCashToWinnerFailed();
    error Lottery__LotteryClosed();
    error Lottery__UpkeepNotNeeded(uint256 currentBalance, uint256 numberOfPlayers, uint256 lotteryState);

    enum LotteryState {
        OPEN,
        CLOSED
    }

    struct LotteryRecord {
        uint256 timeStamp;
        address winner;
        uint256 winningAmount;
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUMBER_OF_WORDS = 1;

    uint256 private immutable i_entryFee;
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gaslane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimestamp;
    address private s_recentWinner;
    LotteryState private s_lotteryState;
    uint256 private s_numberOfLotteriesConducted;

    mapping(uint256 lotteryId => LotteryRecord record) private s_pastLotteries;

    event EnteredLottery(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedLotteryWinner(uint256 indexed requestId);
    event UpkeepChecked(uint256 indexed time);

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
        s_numberOfLotteriesConducted = 0;
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
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasCome = (block.timestamp - s_lastTimestamp) >= i_interval;
        bool isOpen = LotteryState.OPEN == s_lotteryState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasCome && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "0x00");
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("");

        if (!upkeepNeeded) {
            revert Lottery__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_lotteryState));
        }

        s_lotteryState = LotteryState.CLOSED;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gaslane, i_subscriptionId, REQUEST_CONFIRMATIONS, i_callbackGasLimit, NUMBER_OF_WORDS
        );

        emit RequestedLotteryWinner(requestId);
    }

    function fulfillRandomWords(uint256, /* _requestId */ uint256[] memory _randomWords) internal override {
        uint256 indexOfWinner = _randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;

        s_players = new address payable[](0);
        s_lotteryState = LotteryState.OPEN;
        s_lastTimestamp = block.timestamp;
        storeRecord(s_lastTimestamp, winner, address(this).balance);
        s_numberOfLotteriesConducted++;
        emit PickedWinner(winner);

        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Lottery__TransferCashToWinnerFailed();
        }
    }

    function storeRecord(uint256 _timestamp, address _winner, uint256 _winningAmount) private {
        LotteryRecord memory newRecord =
            LotteryRecord({timeStamp: _timestamp, winner: _winner, winningAmount: _winningAmount});

        s_pastLotteries[s_numberOfLotteriesConducted + 1] = newRecord;
    }

    function getEntryFee() external view returns (uint256) {
        return i_entryFee;
    }

    function getLotteryState() external view returns (LotteryState) {
        return s_lotteryState;
    }

    function getPlayerAddressFromIndex(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getPastLotteries() external view returns (LotteryRecord[] memory) {
        LotteryRecord[] memory records = new LotteryRecord[](s_numberOfLotteriesConducted);

        for (uint256 i = 0; i < s_numberOfLotteriesConducted; i++) {
            records[i] = s_pastLotteries[i];
        }
        return records;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimestamp;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }
}
