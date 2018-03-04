const Exchange = artifacts.require('Exchange');
const NFTokenTransferProxy = artifacts.require('NFTokenTransferProxy');
const TokenTransferProxy = artifacts.require('TokenTransferProxy');
const Xcert = artifacts.require('Xcert');
const Xct = artifacts.require('Xct');
const util = require('ethjs-util');
const web3Util = require('web3-utils');
const assertRevert = require('../helpers/assertRevert');

contract('Exchange', (accounts) => {
  let exchange;
  let nfTokenProxy;
  let tokenProxy;
  let token;
  let xcert
  let id1 = web3.sha3('test1');
  let id2 = web3.sha3('test2');
  let id3 = web3.sha3('test3');

  beforeEach(async () => {
    nfTokenProxy = await NFTokenTransferProxy.new();
    tokenProxy = await TokenTransferProxy.new();
    token = await Xct.new();
    xcert = await Xcert.new('Foo', 'F');

    await token.enableTransfer();
    await token.transfer(accounts[1], 200);
    await token.transfer(accounts[2], 200);
    await token.transfer(accounts[3], 200);

    await xcert.mint(accounts[1], id1, 'url');
    await xcert.mint(accounts[2], id2, 'url2');
    await xcert.mint(accounts[3], id3, 'url3');

    exchange = await Exchange.new(token.address, tokenProxy.address, nfTokenProxy.address);
    nfTokenProxy.addAuthorizedAddress(exchange.address);
    tokenProxy.addAuthorizedAddress(exchange.address);
  });

  describe('hashing', function () {
    var testArrayAccount = [accounts[3], accounts[5]];
    var testArrayAmount = [1, 10];
    it('compares the same local and contract hash', async () => {
      var contractHash = await exchange.getTransferDataClaim(accounts[0], accounts[1], accounts[2], 1, testArrayAccount, testArrayAmount, 123);
      var localHash = web3Util.soliditySha3(exchange.address,accounts[0], accounts[1], accounts[2], 1, {t: 'address[]', v:testArrayAccount}, {t: 'uint256[]', v:testArrayAmount}, 123);
      assert.equal(contractHash, localHash);
    });

    it('compares different local and contract hash', async () => {
      var contractHash = await exchange.getTransferDataClaim(accounts[0], accounts[1], accounts[2], 1, testArrayAccount, testArrayAmount, 123);
      var localHash = web3Util.soliditySha3(exchange.address, accounts[0], accounts[1], accounts[2], 1, {t: 'address[]', v:testArrayAccount}, {t: 'uint256[]', v:testArrayAmount}, 124);
      assert.notEqual(contractHash, localHash);
    });
  });

  describe('signature', function () {
    var testArray = [1,2];
    var hash;
    var r;
    var s;
    var v;

    beforeEach(async () => {
      hash = await exchange.getTransferDataClaim(accounts[0], accounts[1], accounts[2], 1, testArray, testArray, 123);
      var signature = web3.eth.sign(accounts[0], hash);

      r = signature.substr(0, 66);
      s = '0x' + signature.substr(66, 64);
      v = parseInt('0x' + signature.substr(130, 2)) + 27;
    });

    it('correctly validates correct signer', async () => {
      var valid = await exchange.isValidSignature(accounts[0], hash, v, r, s);
      assert.equal(valid, true);
    });

    it('correctly validates wrong signer', async () => {
      var valid = await exchange.isValidSignature(accounts[1], hash, v, r, s);
      assert.equal(valid, false);
    });

    it('correctly validates wrong signature data', async () => {
      var valid = await exchange.isValidSignature(accounts[0], hash, 1, 2, 3);
      assert.equal(valid, false);
    });

    it('correctly validates signature data from another accout', async () => {
      var signature = web3.eth.sign(accounts[1], hash);

      r = signature.substr(0, 66);
      s = '0x' + signature.substr(66, 64);
      v = parseInt('0x' + signature.substr(130, 2)) + 27;

      var valid = await exchange.isValidSignature(accounts[0],hash,v,r,s);
      assert.equal(valid, false);

      var valid = await exchange.isValidSignature(accounts[1],hash,v,r,s);
      assert.equal(valid, true);
    });
  });


  describe('transfer', function () {

    describe('valid signature', function () {
      var r;
      var s;
      var v;
      var timestamp;
      var addressArray = [accounts[1]];
      var amountArray = [20];

      var from = accounts[1];
      var to = accounts[2];
      var thirdParty = accounts[3];

      beforeEach(async () => {
        timestamp = 234235345325;
        var hash = web3Util.soliditySha3(exchange.address, from, to, xcert.address, id1, {t: 'address[]', v:addressArray}, {t: 'uint256[]', v:amountArray}, timestamp);
        var signature = web3.eth.sign(from, hash);

        r = signature.substr(0, 66);
        s = '0x' + signature.substr(66, 64);
        v = parseInt('0x' + signature.substr(130, 2)) + 27;
      });

      describe('cancel', function () {

        it('successfuly cancels transfer', async () => {
          var { logs } = await exchange.cancelTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, {from: from});

          let cancelEvent = logs.find(e => e.event === 'LogCancelTransfer');
          assert.notEqual(cancelEvent, undefined);
        });

        it('throws when someone else then the transfer sender tries to cancel it', async () => {
          await assertRevert(exchange.cancelTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, {from: thirdParty}));
        });

        it('throws when trying to cancel an already performed transfer', async () => {

          await token.approve(tokenProxy.address, 20, {from: to});
          await xcert.approve(nfTokenProxy.address, id1, {from: from});

          let { logs } = await exchange.performTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, v, r, s, false, {from: to});

          let event = logs.find(e => e.event === 'LogPerformTransfer');
          assert.notEqual(event, undefined);

          await assertRevert(exchange.cancelTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, {from: to}));
        });

      });

      describe('perform', function () {

        describe('checks enabled', function () {

          it('should transfer successfuly', async () => {

            await token.approve(tokenProxy.address, 20, {from: to});
            await xcert.approve(nfTokenProxy.address, id1, {from: from});

            let { logs } = await exchange.performTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, v, r, s, true, {from: to});

            let event = logs.find(e => e.event === 'LogPerformTransfer');
            assert.notEqual(event, undefined);

            var owner = await xcert.ownerOf(id1);
            var tokenAmountAcc1 = await token.balanceOf(from);
            var tokenAmountAcc2 = await token.balanceOf(to);

            assert.equal(owner, to);
            assert.equal(tokenAmountAcc1, 220);
            assert.equal(tokenAmountAcc2, 180);

          });

          it('should fail with unsofficient allowence', async () => {

            await token.approve(tokenProxy.address, 10, {from: to});
            await xcert.approve(nfTokenProxy.address, id1, {from: from});

            let { logs } = await exchange.performTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, v, r, s, true, {from: to});

            let event = logs.find(e => e.event === 'LogError');
            assert.notEqual(event, undefined);

          });

          it('should fail when not allowed to transfer NFToken', async () => {
            await token.approve(tokenProxy.address, 10, {from: to});

            let { logs } = await exchange.performTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, v, r, s, true, {from: to});

            let event = logs.find(e => e.event === 'LogError');
            assert.notEqual(event, undefined);
          });

          it('throws when fee amount array is no the same length then feeRecipient', async () => {
            await assertRevert(exchange.performTransfer(from, to, xcert.address, id1, addressArray, [20,10], timestamp, v, r, s, true, {from: to}));
          });

          it('throws when _to address is not the one performing transfer', async () => {
            await assertRevert(exchange.performTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, v, r, s, true, {from: thirdParty}));
          });

          it('throws when _to and _from addresses are the same', async () => {
            await assertRevert(exchange.performTransfer(to, to, xcert.address, id1, addressArray, amountArray, timestamp, v, r, s, true, {from: to}));
          });

          it('fails trying to perfom an already performed transfer', async () => {

            await token.approve(tokenProxy.address, 20, {from: to});
            await xcert.approve(nfTokenProxy.address, id1, {from: from});

            var { logs } = await exchange.performTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, v, r, s, true, {from: to});

            let transferEvent = logs.find(e => e.event === 'LogPerformTransfer');
            assert.notEqual(transferEvent, undefined);

            var { logs } = await exchange.performTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, v, r, s, true, {from: to});
            let errorEvent = logs.find(e => e.event === 'LogError');
            assert.notEqual(errorEvent, undefined);
          });

          it('fails trying to perform canceled transfer', async () => {

            var { logs } = await exchange.cancelTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, {from: from});

            let cancelEvent = logs.find(e => e.event === 'LogCancelTransfer');
            assert.notEqual(cancelEvent, undefined);

            var { logs } = await exchange.performTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, v, r, s, true, {from: to});

            let errorEvent = logs.find(e => e.event === 'LogError');
            assert.notEqual(errorEvent, undefined);
          });

        });

        describe('checks disabled', function () {
          it('throws because of unsofficient allowence', async () => {
            await token.approve(tokenProxy.address, 10, {from: to});
            await xcert.approve(nfTokenProxy.address, id1, {from: from});

            await assertRevert(exchange.performTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, v, r, s, false, {from: to}));
          });

          it('throws when not allowed to transfer NFToken', async () => {
            await token.approve(tokenProxy.address, 10, {from: to});

            await assertRevert(exchange.performTransfer(from, to, xcert.address, id1, addressArray, amountArray, timestamp, v, r, s, false, {from: to}));
          });

        });
      });
    });
  });
});
