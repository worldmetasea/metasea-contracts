const TokensSale = artifacts.require("TokensSale");
const Env = require("../env");

module.exports = function (deployer) {
    deployer.deploy(TokensSale, Env.get("TOKENS_VESTING_ADDRESS"));
};
