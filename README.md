# defuma: decentralized fund management

A fund manager creates a fund, invites depositors to earn interest, and makes profit by investing the fund's reserve.

![](https://github.com/chnejohnson/defuma/blob/master/presentation/defuma_logo_landing450.png)

### Description
This project is aimed at a talented fund manager (aka the banker). S/he sets up a fund on the platform and invites investors to deposit capital to the fund contract in order to earn an attractive interest rate.

The banker uses the money in the reserve to make loans. However the investors can withdraw money on demand so the banker must keep a fractional reserve.

There is a mechanism in place to protect the depositors from sudden liquidation. However it’s still a DYOR game. The reputation of the banker is paramount. The platform displays the banker’s statistics but local knowledge trumps numbers.

The banker invests money in loans and other instruments. The investments are tracked on the platform. For instance, if some of the reserve is parked in a DeFi platform the ROI is reported.

When a micro-loan is made the banker records it. But when the money goes to the loanee it’s converted into fiat and enters daily life. Then it’s up to the banker to ensure that the loan gets repaid.

As long as the fund is active interest streams to the investors. It can be fixed or variable. A talented banker can earn an appreciable profit.

At a specified date or result the fund is closed and the initial capital is returned to the investors.

### How it's made
We use Superfluid framework to build a SuperApp. The app is a contract named Loan, which can mint NFT token to loan creditor, so that the borrower can send interest to our contract with specific loan ID, and it would automatically flow interest with money streaming to the lender who possesses the NFT of the loan.