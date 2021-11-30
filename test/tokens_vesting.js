const TokensVesting = artifacts.require("TokensVesting");

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
contract("TokensVesting", function (/* accounts */) {
  it("should assert true", async function () {
    await TokensVesting.deployed();
    return assert.isTrue(true);
  });
});
