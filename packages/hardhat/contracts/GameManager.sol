// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GameManager is Ownable {
    enum PatternType {
        EVEN, // 짝수
        ODD, // 홀수
        PRIME, // 소수
        PI, // π 관련 (314 포함/배수)
        SQUARE // 완전제곱수
    }

    struct Round {
        uint256 roundId;
        uint256 startTime;
        uint256 endTime;
        PatternType pattern;
        uint256 minRange;
        uint256 maxRange;
        bool isActive;
        uint256 rewardPool; // 라운드별 보상 풀 (MM 토큰)
        uint256 remainingRewards; // 남은 보상 개수
    }

    uint256 public currentRoundId;
    uint256 public constant ROUND_DURATION = 600; // 10분
    uint256 public constant REWARD_POOL_SIZE = 100 ether; // 라운드당 100 MM 토큰
    uint256 public constant BASIC_REWARD = 30 ether; // 성공당 30 MM 토큰
    
    IERC20 public mmToken;
    mapping(uint256 => Round) public rounds;

    event NewRoundStarted(
        uint256 indexed roundId,
        PatternType pattern,
        uint256 minRange,
        uint256 maxRange,
        uint256 startTime
    );

    event RoundEnded(uint256 indexed roundId, uint256 endTime, string reason);
    event RewardClaimed(uint256 indexed roundId, address indexed player, uint256 amount);
    event RewardPoolExhausted(uint256 indexed roundId);

    constructor(address _mmToken) Ownable(msg.sender) {
        mmToken = IERC20(_mmToken);
        _startNewRound();
    }

    function getCurrentRound() external view returns (Round memory) {
        return rounds[currentRoundId];
    }

    function isRoundActive() external view returns (bool) {
        Round memory round = rounds[currentRoundId];
        return round.isActive && block.timestamp < round.endTime;
    }

    function startNewRound() external onlyOwner {
        _startNewRound();
    }

    function _startNewRound() internal {
        // 이전 라운드 종료
        if (currentRoundId > 0) {
            rounds[currentRoundId].isActive = false;
            emit RoundEnded(currentRoundId, block.timestamp, "New round started");
        }

        currentRoundId++;

        // 새 라운드 패턴 및 범위 설정
        (PatternType pattern, uint256 minRange, uint256 maxRange) = _generateRoundParameters();

        rounds[currentRoundId] = Round({
            roundId: currentRoundId,
            startTime: block.timestamp,
            endTime: block.timestamp + ROUND_DURATION,
            pattern: pattern,
            minRange: minRange,
            maxRange: maxRange,
            isActive: true,
            rewardPool: REWARD_POOL_SIZE,
            remainingRewards: REWARD_POOL_SIZE / BASIC_REWARD
        });

        emit NewRoundStarted(currentRoundId, pattern, minRange, maxRange, block.timestamp);
    }

    function _generateRoundParameters() internal view returns (PatternType, uint256, uint256) {
        // 의사 랜덤으로 패턴과 범위 생성
        uint256 rand = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, currentRoundId)));

        // 완전 랜덤한 패턴 선택
        PatternType pattern = PatternType(rand % 5);

        // 완전 랜덤한 범위 생성
        uint256 baseRange = 30000; // 최소 기준값
        uint256 maxRangeSpread = 50000; // 최대 범위 확산

        // 랜덤한 최소값 생성 (30,000 ~ 70,000)
        uint256 minRange = baseRange + (rand % (maxRangeSpread + 1));

        // 랜덤한 범위 크기 생성 (10,000 ~ 30,000)
        uint256 rangeSize = 10000 + ((rand >> 8) % 20001);
        uint256 maxRange = minRange + rangeSize;

        return (pattern, minRange, maxRange);
    }

    function autoAdvanceRound() external {
        require(
            block.timestamp >= rounds[currentRoundId].endTime || rounds[currentRoundId].remainingRewards == 0,
            "Round still active and rewards available"
        );
        
        string memory reason = rounds[currentRoundId].remainingRewards == 0 
            ? "Reward pool exhausted" 
            : "Time expired";
            
        rounds[currentRoundId].isActive = false;
        emit RoundEnded(currentRoundId, block.timestamp, reason);
        
        _startNewRound();
    }
    
    // 보상 지급 함수 (MiningEngine에서 호출)
    function claimReward(address player) external returns (bool) {
        Round storage round = rounds[currentRoundId];
        require(round.isActive, "Round not active");
        require(round.remainingRewards > 0, "No rewards remaining");
        
        // MM 토큰 전송
        require(mmToken.transfer(player, BASIC_REWARD), "Token transfer failed");
        
        round.remainingRewards--;
        round.rewardPool -= BASIC_REWARD;
        
        emit RewardClaimed(currentRoundId, player, BASIC_REWARD);
        
        // 보상풀이 소진되면 라운드 종료
        if (round.remainingRewards == 0) {
            emit RewardPoolExhausted(currentRoundId);
            round.isActive = false;
            emit RoundEnded(currentRoundId, block.timestamp, "Reward pool exhausted");
            _startNewRound();
        }
        
        return true;
    }

    function getRoundHistory(uint256 count) external view returns (Round[] memory) {
        uint256 startId = currentRoundId > count ? currentRoundId - count + 1 : 1;
        uint256 actualCount = currentRoundId - startId + 1;

        Round[] memory history = new Round[](actualCount);
        for (uint256 i = 0; i < actualCount; i++) {
            history[i] = rounds[startId + i];
        }

        return history;
    }
}
