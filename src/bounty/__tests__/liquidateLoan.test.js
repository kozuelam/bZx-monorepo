import { pathOr } from "ramda";
import b0xJS from "../../core/__tests__/setup";
import * as FillTestUtils from "../../fill/__tests__/utils";
import B0xJS from "../../core";
import { expectPromiEvent } from "../../core/__tests__/utils";

const { web3 } = b0xJS;

describe("bounty", () => {
  const { owner, lenders, traders } = FillTestUtils.getAccounts();

  const {
    loanTokens,
    interestTokens,
    collateralTokens
  } = FillTestUtils.initAllContractInstances();

  const order = FillTestUtils.makeOrderAsLender({
    web3,
    lenders,
    loanTokens,
    interestTokens
  });

  const collateralTokenFilled = collateralTokens[0].options.address.toLowerCase();
  const takerAddress = traders[0];

  let orderHashHex = null;

  beforeAll(async () => {
    const transferAmount = web3.utils.toWei("4000", "ether");
    await FillTestUtils.setupAll({ owner, lenders, traders, transferAmount });

    const txOpts = {
      from: takerAddress,
      gas: 1000000,
      gasPrice: web3.utils.toWei("30", "gwei").toString()
    };

    orderHashHex = B0xJS.getLoanOrderHashHex(order);
    const signature = await b0xJS.signOrderHashAsync(
      orderHashHex,
      order.makerAddress
    );

    const loanTokenAmountFilled = web3.utils.toWei("12.3");

    const receipt = await b0xJS.takeLoanOrderAsTrader(
      { ...order, signature },
      collateralTokenFilled,
      loanTokenAmountFilled,
      txOpts
    );

    expect(pathOr(null, ["events", "DebugLine"], receipt)).toEqual(null);
  });

  describe("liquidateLoan", () => {
    test("should liquidate the loan", async () => {
      const loansBefore = await b0xJS.getActiveLoans({
        start: 0,
        count: 10
      });

      const promiEvent = b0xJS.liquidateLoan({
        loanOrderHash: orderHashHex,
        trader: traders[0],
        txOpts: {
          from: lenders[0],
          gas: 1000000,
          gasPrice: web3.utils.toWei("30", "gwei").toString()
        }
      });

      expectPromiEvent(promiEvent);

      const loansAfter = await b0xJS.getActiveLoans({ start: 0, count: 10 });

      const thisLoanBefore = loansBefore.filter(
        loan => loan.loanOrderHash === orderHashHex
      );
      const thisLoanAfter = loansAfter.filter(
        loan => loan.loanOrderHash === orderHashHex
      );

      expect(thisLoanBefore.length).toEqual(1);
      expect(thisLoanAfter.length).toEqual(0);
    });
  });
});
