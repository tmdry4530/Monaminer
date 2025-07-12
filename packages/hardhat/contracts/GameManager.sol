// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MinerNFT.sol";

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
        PatternType pattern;
        uint256 minRange;
        uint256 maxRange;
        bool isActive;
        uint256 rewardPool; // 라운드별 보상 풀 (MM 토큰)
        uint256 remainingRewards; // 남은 보상 개수
    }

    uint256 public currentRoundId;
    uint256 public constant REWARD_POOL_SIZE = 100 ether; // 라운드당 100 MM 토큰
    uint256 public constant BASIC_REWARD = 30 ether; // 성공당 30 MM 토큰

    IERC20 public mmToken;
    MinerNFT public minerNFT;
    mapping(uint256 => Round) public rounds;
    bool public initialNFTsMinted; // 최초 NFT 민팅 여부

    event NewRoundStarted(
        uint256 indexed roundId,
        PatternType pattern,
        uint256 minRange,
        uint256 maxRange,
        uint256 startTime
    );

    event RoundEnded(uint256 indexed roundId, uint256 endTime);
    event RewardClaimed(uint256 indexed roundId, address indexed player, uint256 amount);
    event RewardPoolExhausted(uint256 indexed roundId);
    event StartingNFTsMinted(uint256 indexed roundId, address indexed recipient, uint256[3] tokenIds);

    constructor(address _mmToken, address _minerNFT) Ownable(msg.sender) {
        mmToken = IERC20(_mmToken);
        minerNFT = MinerNFT(_minerNFT);
        initialNFTsMinted = false;
        _startNewRound();
    }
    
    // 초기화 함수 (배포 후 별도로 호출) - 최초 한번만
    function initializeWithNFTs() external onlyOwner {
        require(!initialNFTsMinted, "Initial NFTs already minted");
        _mintStartingNFTs();
        initialNFTsMinted = true;
    }

    function getCurrentRound() external view returns (Round memory) {
        return rounds[currentRoundId];
    }

    function isRoundActive() external view returns (bool) {
        if (currentRoundId == 0) return false;
        Round memory round = rounds[currentRoundId];
        return round.isActive && round.remainingRewards > 0;
    }
    
    // 라운드 종료 조건 확인 (보상풀 소진 시에만)
    function shouldRoundEnd() external view returns (bool) {
        if (currentRoundId == 0) return false;
        Round memory round = rounds[currentRoundId];
        return round.isActive && round.remainingRewards == 0;
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
            pattern: pattern,
            minRange: minRange,
            maxRange: maxRange,
            isActive: true,
            rewardPool: REWARD_POOL_SIZE,
            remainingRewards: REWARD_POOL_SIZE / BASIC_REWARD
        });

        emit NewRoundStarted(currentRoundId, pattern, minRange, maxRange, block.timestamp);
    }

    function _mintStartingNFTs() internal {
        // 3개의 다른 타입 NFT 민팅 (BalancedScan 3개)
        MinerNFT.MinerType[] memory minerTypes = new MinerNFT.MinerType[](3);
        minerTypes[0] = MinerNFT.MinerType.BALANCED_SCAN;
        minerTypes[1] = MinerNFT.MinerType.BALANCED_SCAN;
        minerTypes[2] = MinerNFT.MinerType.BALANCED_SCAN;

        // 배포자(owner)에게 NFT 민팅
        uint256[] memory tokenIds = minerNFT.batchMintMiners(owner(), minerTypes);

        uint256[3] memory nftIds;
        nftIds[0] = tokenIds[0];
        nftIds[1] = tokenIds[1];
        nftIds[2] = tokenIds[2];

        emit StartingNFTsMinted(currentRoundId, owner(), nftIds);
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
            rounds[currentRoundId].remainingRewards == 0,
            "Round still active, rewards available"
        );

        rounds[currentRoundId].isActive = false;
        emit RoundEnded(currentRoundId, block.timestamp);

        // 새 라운드는 별도로 startNewRound() 함수를 호출해야 함
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

        // 보상풀이 소진되면 라운드 종료 (새 라운드는 수동으로 시작해야 함)
        if (round.remainingRewards == 0) {
            emit RewardPoolExhausted(currentRoundId);
            round.isActive = false;
            emit RoundEnded(currentRoundId, block.timestamp);
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
    
    // 보상풀 상태 조회
    function getRewardPoolStatus(uint256 roundId) external view returns (uint256 remaining, uint256 total) {
        Round memory round = rounds[roundId];
        return (round.remainingRewards, REWARD_POOL_SIZE / BASIC_REWARD);
    }
    
    // 현재 라운드 보상풀 상태 조회
    function getCurrentRewardPoolStatus() external view returns (uint256 remaining, uint256 total) {
        Round memory round = rounds[currentRoundId];
        return (round.remainingRewards, REWARD_POOL_SIZE / BASIC_REWARD);
    }
    
    // 컨트랙트에 MM 토큰 충전 (소유자만)
    function fundContract(uint256 amount) external onlyOwner {
        require(mmToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }
    
    // MM 토큰 출금 (소유자만)
    function withdrawTokens(address to, uint256 amount) external onlyOwner {
        require(mmToken.transfer(to, amount), "Transfer failed");
    }
    
    // 컨트랙트 잔액 조회
    function getContractBalance() external view returns (uint256) {
        return mmToken.balanceOf(address(this));
    }
}
