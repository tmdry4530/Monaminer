import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { Contract } from "ethers";

const setupContracts: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();

  // Get all deployed contracts
  const gameManager = await hre.ethers.getContract<Contract>("GameManager", deployer);
  const minerNFT = await hre.ethers.getContract<Contract>("MinerNFT", deployer);
  const rewardManager = await hre.ethers.getContract<Contract>("RewardManager", deployer);
  const gachaSystem = await hre.ethers.getContract<Contract>("GachaSystem", deployer);
  const miningEngine = await hre.ethers.getContract<Contract>("MiningEngine", deployer);
  const mmToken = await hre.ethers.getContract<Contract>("MMToken", deployer);

  console.log("\n=== 🎮 Monaminer 컨트랙트 배포 완료 ===");
  console.log("🎯 GameManager:", await gameManager.getAddress());
  console.log("⛏️ MinerNFT:", await minerNFT.getAddress());
  console.log("🎁 RewardManager:", await rewardManager.getAddress());
  console.log("🎰 GachaSystem:", await gachaSystem.getAddress());
  console.log("⚒️ MiningEngine:", await miningEngine.getAddress());
  console.log("💰 MMToken:", await mmToken.getAddress());

  // 권한 설정 (필요한 경우)
  console.log("\n=== 권한 설정 시작 ===");

  try {
    // MinerNFT에 GachaSystem이 mint할 수 있도록 권한 부여
    console.log("🔗 GachaSystem에 MinerNFT minting 권한 부여...");
    const tx1 = await minerNFT.setMinter(await gachaSystem.getAddress(), true);
    await tx1.wait();
    console.log("✅ GachaSystem minting 권한 설정 완료");

    // RewardManager에 MiningEngine이 보상을 분배할 수 있도록 권한 부여
    console.log("🔗 MiningEngine에 RewardManager 권한 부여...");
    const tx2 = await rewardManager.setMiningEngine(await miningEngine.getAddress());
    await tx2.wait();
    console.log("✅ MiningEngine 보상 분배 권한 설정 완료");

    // GameManager에 보상풀용 MM 토큰 충전 (1000 MM 토큰)
    console.log("🔗 GameManager에 MM 토큰 충전 중...");
    const fundAmount = hre.ethers.parseEther("1000"); // 1000 MM 토큰
    const tx3 = await mmToken.transfer(await gameManager.getAddress(), fundAmount);
    await tx3.wait();
    console.log("✅ GameManager에 1000 MM 토큰 충전 완료");

    // 현재 라운드 보상풀 상태 확인
    console.log("🔍 현재 라운드 보상풀 상태 확인...");
    const rewardStatus = await gameManager.getCurrentRewardPoolStatus();
    console.log(`📊 보상풀 상태: ${rewardStatus[0]}/${rewardStatus[1]} 개 남음`);
  } catch (error) {
    console.log("⚠️ 권한 설정 중 오류 발생 (일부 함수가 없을 수 있음):", error);
  }

  console.log("\n=== 🚀 모든 컨트랙트 배포 및 설정 완료! ===");
  console.log("디버깅을 위해 다음 주소들을 사용하세요:");
  console.log(`GameManager: ${await gameManager.getAddress()}`);
  console.log(`MinerNFT: ${await minerNFT.getAddress()}`);
  console.log(`RewardManager: ${await rewardManager.getAddress()}`);
  console.log(`GachaSystem: ${await gachaSystem.getAddress()}`);
  console.log(`MiningEngine: ${await miningEngine.getAddress()}`);
  console.log(`MMToken: ${await mmToken.getAddress()}`);
};

export default setupContracts;

setupContracts.tags = ["Setup"];
setupContracts.dependencies = ["GameManager", "MinerNFT", "RewardManager", "GachaSystem", "MiningEngine"];
setupContracts.runAtTheEnd = true;
