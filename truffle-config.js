var HDWalletProvider = require("truffle-hdwallet-provider");
var mnemonic = "tissue buyer coffee clinic traffic grain sorry grain match project secret ten";

module.exports = {
  networks: {
    development: {
      provider: function() {
        return new HDWalletProvider(mnemonic, "http://127.0.0.1:7545/", 0, 100);
      },
      network_id: '*',
    }
  },
  compilers: {
    solc: {
      version: "^0.4.24"
    }
  }
};