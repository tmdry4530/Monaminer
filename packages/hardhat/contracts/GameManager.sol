// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

contract GameManager is Ownable {
    enum PatternType {
        EVEN,    // 짝수
        ODD,     // 홀수
        PRIME,   // 소수
        PI,      // π 관련 (314 포함/배수)
        SQUARE   // 완전제곱수
    }

    struct Round {
        uint256 roundId;
        uint256 startTime;
        uint256 endTime;
        PatternType pattern;
        uint256 minRange;
        uint256 maxRange;
        bool isActive;
    }

    uint256 public currentRoundId;
    uint256 public constant ROUND_DURATION = 600; // 10분
    mapping(uint256 => Round) public rounds;
    
    event NewRoundStarted(
        uint256 indexed roundId,
        PatternType pattern,
        uint256 minRange,
        uint256 maxRange,
        uint256 startTime
    );
    
    event RoundEnded(uint256 indexed roundId, uint256 endTime);

    constructor() Ownable(msg.sender) {
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
            emit RoundEnded(currentRoundId, block.timestamp);
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
            isActive: true
        });

        emit NewRoundStarted(
            currentRoundId,
            pattern,
            minRange,
            maxRange,
            block.timestamp
        );
    }

    function _generateRoundParameters() internal view returns (PatternType, uint256, uint256) {
        // 의사 랜덤으로 패턴과 범위 생성
        uint256 rand = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            currentRoundId
        )));

        PatternType pattern = PatternType(rand % 5);
        
        uint256 minRange;
        uint256 maxRange;
        
        // 패턴별 범위 설정 (PRD 기준)
        if (pattern == PatternType.EVEN) {
            minRange = 40000;
            maxRange = 60000;
        } else if (pattern == PatternType.PRIME) {
            minRange = 74000;
            maxRange = 80000;
        } else if (pattern == PatternType.PI) {
            minRange = 60000;
            maxRange = 70000;
        } else if (pattern == PatternType.SQUARE) {
            minRange = 30000;
            maxRange = 50000;
        } else { // ALL (BalancedScan)
            minRange = 50000;
            maxRange = 70000;
        }

        return (pattern, minRange, maxRange);
    }

    function autoAdvanceRound() external {
        require(block.timestamp >= rounds[currentRoundId].endTime, "Round still active");
        _startNewRound();
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