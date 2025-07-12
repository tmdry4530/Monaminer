import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { Contract } from "ethers";

const deployGachaSystem: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy, get } = hre.deployments;

  // Get previously deployed contracts
  const minerNFT = await get("MinerNFT");
  const mmToken = await get("MMToken");

  await deploy("GachaSystem", {
    from: deployer,
    args: [minerNFT.address, mmToken.address],
    log: true,
    autoMine: true,
  });

  // Get the deployed contract to interact with it after deploying.
  const gachaSystem = await hre.ethers.getContract<Contract>("GachaSystem", deployer);
  console.log("🎰 GachaSystem deployed to:", await gachaSystem.getAddress());
  console.log("📄 MM Token Address:", mmToken.address);
};

export default deployGachaSystem;

deployGachaSystem.tags = ["GachaSystem"];
deployGachaSystem.dependencies = ["MinerNFT", "MMToken"];
