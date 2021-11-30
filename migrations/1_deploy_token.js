const MetaSea = artifacts.require("MetaSea");
const Env = require('../env');

module.exports = function (deployer) {
    deployer.deploy(MetaSea, Env.get('TOKEN_NAME'), Env.get('TOKEN_SYMBOL'));
};