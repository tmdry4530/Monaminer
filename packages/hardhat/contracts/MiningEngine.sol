// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./GameManager.sol";
import "./MinerNFT.sol";
import "./RewardManager.sol";

contract MiningEngine is Ownable, ReentrancyGuard {
    GameManager public gameManager;
    MinerNFT public minerNFT;
    RewardManager public rewardManager;

    struct MiningSession {
        address player;
        uint256[3] nftIds;
        uint256 roundId;
        uint256 startTime;
        bool isActive;
        uint256 totalAttempts;
        uint256 totalSuccesses;
        uint256 lastMiningTime;
        bool autoMining; // 자동 채굴 상태
        uint256 nextAutoMiningTime; // 다음 자동 채굴 시간
    }

    struct MiningAttempt {
        address player;
        uint256 nftId;
        uint256 roundId;
        uint256 randomNumber;
        bool success;
        uint256 timestamp;
    }


    uint256 public constant TPS_PER_MINER = 50; // 초당 50 트랜잭션
    uint256 public constant MINING_INTERVAL = 200; // 0.2초 (200ms)
    uint256 public constant BATCH_SIZE = 10; // 배치당 10개 트랜잭션

    mapping(address => MiningSession) public activeSessions;
    mapping(address => MiningAttempt[]) public miningHistory;
    mapping(address => uint256) public playerTotalSuccesses;
    mapping(address => bool) public autoMiningEnabled; // 플레이어별 자동 채굴 활성화 상태

    event MiningSessionStarted(address indexed player, uint256[3] nftIds, uint256 roundId, uint256 startTime);

    event MiningSuccess(
        address indexed player,
        uint256 indexed nftId,
        uint256 randomNumber,
        uint256 roundId,
        uint256 timestamp
    );

    event MiningSessionEnded(address indexed player, uint256 totalAttempts, uint256 totalSuccesses, uint256 endTime);

    event BatchMiningCompleted(address indexed player, uint256 batchAttempts, uint256 batchSuccesses);
    
    event AutoMiningStarted(address indexed player);
    event AutoMiningStopped(address indexed player);
    event AutoMiningBatch(address indexed player, uint256 batchSuccesses);

    constructor(
        address _gameManager,
        address _minerNFT,
        address _rewardManager
    ) Ownable(msg.sender) {
        gameManager = GameManager(_gameManager);
        minerNFT = MinerNFT(_minerNFT);
        rewardManager = RewardManager(_rewardManager);
    }

    function startMining(uint256[3] calldata nftIds) external nonReentrant {
        require(!activeSessions[msg.sender].isActive, "Already mining");
        require(gameManager.isRoundActive(), "No active round");

        // NFT 소유권 확인
        for (uint256 i = 0; i < 3; i++) {
            require(minerNFT.ownerOf(nftIds[i]) == msg.sender, "Not NFT owner");
        }

        GameManager.Round memory currentRound = gameManager.getCurrentRound();

        activeSessions[msg.sender] = MiningSession({
            player: msg.sender,
            nftIds: nftIds,
            roundId: currentRound.roundId,
            startTime: block.timestamp,
            isActive: true,
            totalAttempts: 0,
            totalSuccesses: 0,
            lastMiningTime: block.timestamp,
            autoMining: false,
            nextAutoMiningTime: 0
        });

        emit MiningSessionStarted(msg.sender, nftIds, currentRound.roundId, block.timestamp);
    }

    function performBatchMining() external nonReentrant {
        MiningSession storage session = activeSessions[msg.sender];
        require(session.isActive, "No active session");
        require(block.timestamp >= session.lastMiningTime + (MINING_INTERVAL / 1000), "Mining too fast");

        GameManager.Round memory currentRound = gameManager.getCurrentRound();
        require(session.roundId == currentRound.roundId, "Round changed");

        uint256 batchSuccesses = 0;

        // 3개 NFT × 10개씩 = 30개 배치 처리 (시드 기반 랜덤)
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < BATCH_SIZE; j++) {
                uint256 randomNumber = _generateRandomNumber(session.nftIds[i], j, session.totalAttempts);
                
                // 채굴 성공 여부 확인
                bool success = _checkMiningSuccess(randomNumber, session.nftIds[i], currentRound);
                
                if (success) {
                    batchSuccesses++;
                    session.totalSuccesses++;
                    playerTotalSuccesses[msg.sender]++;

                    // 성공 기록
                    miningHistory[msg.sender].push(
                        MiningAttempt({
                            player: msg.sender,
                            nftId: session.nftIds[i],
                            roundId: session.roundId,
                            randomNumber: randomNumber,
                            success: true,
                            timestamp: block.timestamp
                        })
                    );

                    // GameManager에서 보상 지급
                    gameManager.claimReward(msg.sender);

                    emit MiningSuccess(msg.sender, session.nftIds[i], randomNumber, session.roundId, block.timestamp);
                }

                session.totalAttempts++;
            }
        }

        session.lastMiningTime = block.timestamp;

        emit BatchMiningCompleted(msg.sender, BATCH_SIZE * 3, batchSuccesses);

    }

    function stopMining() external {
        require(activeSessions[msg.sender].isActive, "No active session");
        _endMiningSession(msg.sender);
    }

    // 자동 채굴 시작
    function startAutoMining() external {
        MiningSession storage session = activeSessions[msg.sender];
        require(session.isActive, "No active session");
        require(!session.autoMining, "Auto mining already active");
        
        session.autoMining = true;
        session.nextAutoMiningTime = block.timestamp + (MINING_INTERVAL / 1000);
        autoMiningEnabled[msg.sender] = true;
        
        emit AutoMiningStarted(msg.sender);
    }

    // 자동 채굴 정지
    function stopAutoMining() external {
        MiningSession storage session = activeSessions[msg.sender];
        require(session.isActive, "No active session");
        require(session.autoMining, "Auto mining not active");
        
        session.autoMining = false;
        session.nextAutoMiningTime = 0;
        autoMiningEnabled[msg.sender] = false;
        
        emit AutoMiningStopped(msg.sender);
    }

    // 자동 채굴 배치 실행 (외부에서 호출 가능)
    function executeAutoMining(address player) external {
        MiningSession storage session = activeSessions[player];
        require(session.isActive, "No active session");
        require(session.autoMining, "Auto mining not enabled");
        require(block.timestamp >= session.nextAutoMiningTime, "Auto mining cooldown");

        GameManager.Round memory currentRound = gameManager.getCurrentRound();
        require(session.roundId == currentRound.roundId, "Round changed");

        uint256 batchSuccesses = 0;

        // 3개 NFT × 10개씩 = 30개 배치 처리 (자동)
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < BATCH_SIZE; j++) {
                uint256 randomNumber = _generateRandomNumber(session.nftIds[i], j, session.totalAttempts);
                
                // 채굴 성공 여부 확인
                bool success = _checkMiningSuccess(randomNumber, session.nftIds[i], currentRound);
                
                if (success) {
                    batchSuccesses++;
                    session.totalSuccesses++;
                    playerTotalSuccesses[player]++;

                    // 성공 기록
                    miningHistory[player].push(
                        MiningAttempt({
                            player: player,
                            nftId: session.nftIds[i],
                            roundId: session.roundId,
                            randomNumber: randomNumber,
                            success: true,
                            timestamp: block.timestamp
                        })
                    );

                    // GameManager에서 보상 지급
                    gameManager.claimReward(player);

                    emit MiningSuccess(player, session.nftIds[i], randomNumber, session.roundId, block.timestamp);
                }

                session.totalAttempts++;
            }
        }

        // 다음 자동 채굴 시간 설정
        session.lastMiningTime = block.timestamp;
        session.nextAutoMiningTime = block.timestamp + (MINING_INTERVAL / 1000);

        emit AutoMiningBatch(player, batchSuccesses);

    }

    function _endMiningSession(address player) internal {
        MiningSession storage session = activeSessions[player];

        // 자동 채굴 정지
        if (session.autoMining) {
            session.autoMining = false;
            autoMiningEnabled[player] = false;
            emit AutoMiningStopped(player);
        }

        // 완주 보너스 체크 (90,000 트랜잭션)
        if (session.totalAttempts >= 90000) {
            rewardManager.distributeCompletionBonus(player);
        }

        emit MiningSessionEnded(player, session.totalAttempts, session.totalSuccesses, block.timestamp);

        session.isActive = false;
    }

    function _generateRandomNumber(uint256 nftId, uint256 seed, uint256 totalAttempts) internal view returns (uint256) {
        // 블록 데이터와 사용자 데이터를 조합한 시드 기반 랜덤값 생성
        return uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    msg.sender,
                    nftId,
                    seed,
                    totalAttempts,
                    gasleft()
                )
            )
        );
    }

    function _checkMiningSuccess(
        uint256 randomNumber,
        uint256 nftId,
        GameManager.Round memory round
    ) internal view returns (bool) {
        // 범위 체크
        uint256 targetNumber = (randomNumber % (round.maxRange - round.minRange + 1)) + round.minRange;

        // 패턴 체크
        bool patternMatch = _checkPattern(targetNumber, round.pattern);
        if (!patternMatch) {
            return false;
        }

        // 성공률 체크
        uint256 effectiveSuccessRate = minerNFT.calculateEffectiveSuccessRate(nftId, round.pattern);
        uint256 successThreshold = (randomNumber % 10000);

        return successThreshold < effectiveSuccessRate;
    }

    function _checkPattern(uint256 number, GameManager.PatternType pattern) internal pure returns (bool) {
        if (pattern == GameManager.PatternType.EVEN) {
            return number % 2 == 0;
        } else if (pattern == GameManager.PatternType.ODD) {
            return number % 2 == 1;
        } else if (pattern == GameManager.PatternType.PRIME) {
            return _isPrime(number);
        } else if (pattern == GameManager.PatternType.PI) {
            return _isPiRelated(number);
        } else if (pattern == GameManager.PatternType.SQUARE) {
            return _isPerfectSquare(number);
        }
        return false;
    }

    function _isPrime(uint256 n) internal pure returns (bool) {
        if (n < 2) return false;
        if (n == 2) return true;
        if (n % 2 == 0) return false;

        for (uint256 i = 3; i * i <= n; i += 2) {
            if (n % i == 0) return false;
        }
        return true;
    }

    function _isPiRelated(uint256 n) internal pure returns (bool) {
        // 314를 포함하거나 314의 배수
        string memory numStr = _toString(n);
        return _contains(numStr, "314") || n % 314 == 0;
    }

    function _isPerfectSquare(uint256 n) internal pure returns (bool) {
        if (n == 0) return true;
        uint256 sqrt = _sqrt(n);
        return sqrt * sqrt == n;
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 result = 1;
        if (x >> 128 > 0) {
            x >>= 128;
            result <<= 64;
        }
        if (x >> 64 > 0) {
            x >>= 64;
            result <<= 32;
        }
        if (x >> 32 > 0) {
            x >>= 32;
            result <<= 16;
        }
        if (x >> 16 > 0) {
            x >>= 16;
            result <<= 8;
        }
        if (x >> 8 > 0) {
            x >>= 8;
            result <<= 4;
        }
        if (x >> 4 > 0) {
            x >>= 4;
            result <<= 2;
        }
        if (x >> 2 > 0) {
            result <<= 1;
        }
        return result;
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _contains(string memory str, string memory substr) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory substrBytes = bytes(substr);

        if (substrBytes.length > strBytes.length) return false;

        for (uint256 i = 0; i <= strBytes.length - substrBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < substrBytes.length; j++) {
                if (strBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    // 조회 함수들
    function getMiningStats(
        address player
    )
        external
        view
        returns (uint256 attempts, uint256 successes, uint256 currentTPS, bool isActive, uint256 remainingTime)
    {
        MiningSession memory session = activeSessions[player];
        uint256 elapsed = block.timestamp - session.startTime;

        return (
            session.totalAttempts,
            session.totalSuccesses,
            elapsed > 0 ? session.totalAttempts / elapsed : 0,
            session.isActive,
            0 // 시간 제한 없음
        );
    }

    // 자동 채굴 상태 조회
    function getAutoMiningStatus(address player) 
        external 
        view 
        returns (bool isAutoMining, uint256 nextMiningTime, uint256 cooldownRemaining) 
    {
        MiningSession memory session = activeSessions[player];
        
        uint256 cooldown = 0;
        if (session.nextAutoMiningTime > block.timestamp) {
            cooldown = session.nextAutoMiningTime - block.timestamp;
        }
        
        return (
            session.autoMining,
            session.nextAutoMiningTime,
            cooldown
        );
    }

    // 자동 채굴 실행 가능 여부 확인
    function canExecuteAutoMining(address player) external view returns (bool) {
        MiningSession memory session = activeSessions[player];
        
        return session.isActive && 
               session.autoMining && 
               block.timestamp >= session.nextAutoMiningTime;
    }

    function getMiningHistory(address player, uint256 limit) external view returns (MiningAttempt[] memory) {
        MiningAttempt[] memory history = miningHistory[player];
        if (limit == 0 || limit > history.length) {
            return history;
        }

        MiningAttempt[] memory limitedHistory = new MiningAttempt[](limit);
        uint256 startIndex = history.length - limit;
        for (uint256 i = 0; i < limit; i++) {
            limitedHistory[i] = history[startIndex + i];
        }
        return limitedHistory;
    }

    function getRecentSuccesses(uint256 count) external view returns (MiningAttempt[] memory) {
        // 최근 성공 사례들을 반환 (메타 게임용)
        // 간단한 구현으로 현재 플레이어의 성공만 반환
        MiningAttempt[] memory history = miningHistory[msg.sender];
        if (count == 0 || count > history.length) {
            return history;
        }

        MiningAttempt[] memory limitedHistory = new MiningAttempt[](count);
        uint256 startIndex = history.length - count;
        for (uint256 i = 0; i < count; i++) {
            limitedHistory[i] = history[startIndex + i];
        }
        return limitedHistory;
    }


    // Admin functions
    function setGameManager(address _gameManager) external onlyOwner {
        gameManager = GameManager(_gameManager);
    }

    function setMinerNFT(address _minerNFT) external onlyOwner {
        minerNFT = MinerNFT(_minerNFT);
    }

    function setRewardManager(address _rewardManager) external onlyOwner {
        rewardManager = RewardManager(_rewardManager);
    }

    function forceEndSession(address player) external onlyOwner {
        require(activeSessions[player].isActive, "No active session");
        _endMiningSession(player);
    }
}
