/**
 * Copyright 2017-2020, bZeroX, LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0.
 */

pragma solidity 0.5.8;

import "./BZxBridge.sol";


interface CDPManager {
    function ilks(uint cdp) external view returns (bytes32);
    function urns(uint cdp) external view returns(address);
    function cdpCan(address owner, uint cdp, address allowed) external view returns(bool);

    function frob(uint cdp, int dink, int dart) external;
    function flux(uint cdp, address dst, uint wad) external;
}

interface JoinAdapter {
    function ilk() external view returns (bytes32);
    function gem() external view returns (address);

    function join(address urn, uint dart) external;
    function exit(address usr, uint wad) external;
}

contract MakerBridge is BZxBridge
{
    address public dai;
    address public joinDAI;

    LoanTokenInterface public iDai;
    CDPManager public cdpManager;

    mapping(bytes32 => address) public joinAdapters; // ilk => join adapter address
    mapping(bytes32 => address) public gems; // ilk => underlying token address
    mapping(bytes32 => address) public tokens; // ilk => iToken address

    event NewAddresses(bytes32 ilk, address joinAdapter, address iToken);

    constructor(
        address _iDai,
        address _cdpManager,
        address _joinDAI,
        address[] memory _joinAdapters,
        address[] memory iTokens
    ) public {
        joinDAI = _joinDAI;

        iDai = LoanTokenInterface(_iDai);
        dai = iDai.loanTokenAddress();

        cdpManager = CDPManager(_cdpManager);

        setAddresses(_joinAdapters, iTokens);
    }

    function migrateLoan(
        uint[] memory cdps, // ids
        uint[] memory darts, // DAI amounts
        uint[] memory dinks, // other amounts
        uint[] memory collateralDinks, // will be used for borrow on bZx
        uint[] memory borrowAmounts // the amounts of underlying tokens for each new Torque loan
    )
        public
    {
        require(cdps.length > 0, "Invalid cdps");
        require(cdps.length == darts.length, "Invalid darts");
        require(darts.length == dinks.length, "Invalid dinks");
        require(collateralDinks.length == dinks.length, "Invalid collateral dinks");
        require(collateralDinks.length == borrowAmounts.length, "Invalid borrow amounts length");

        uint loanAmount;
        uint totalBorrowAmount;
        for (uint i = 0; i < darts.length; i++) {
            loanAmount += darts[i];
            totalBorrowAmount += borrowAmounts[i];
        }
        require(totalBorrowAmount == loanAmount, "Invalid borrow amounts value");

        bytes memory data = abi.encodeWithSignature(
            "_migrateLoan(address,uint256[],uint256[],uint256[],uint256[],uint256,uint256[])",
            msg.sender, cdps, darts, dinks, collateralDinks, loanAmount, borrowAmounts
        );

        iDai.flashBorrowToken(loanAmount, address(this), address(this), "", data);
    }

    function _migrateLoan(
        address borrower,
        uint[] memory cdps,
        uint[] memory darts,
        uint[] memory dinks,
        uint[] memory collateralDinks,
        uint loanAmount,
        uint[] memory borrowAmounts
    )
        public
    {
        ERC20(dai).approve(joinDAI, loanAmount);

        address _borrower = borrower;
        for (uint i = 0; i < cdps.length; i++) {
            uint cdp = cdps[i];
            uint dart = darts[i];
            uint dink = dinks[i];
            uint collateralDink = collateralDinks[i];

            requireThat(cdpManager.cdpCan(_borrower, cdp, address(this)), "cdp-not-allowed", i);
            requireThat(collateralDink <= dink, "Collateral amount exceeds total value (dink)", i);

            address urn = cdpManager.urns(cdp);
            JoinAdapter(joinDAI).join(urn, dart);

            cdpManager.frob(cdp, -int(dink), 0);
            cdpManager.flux(cdp, address(this), dink);

            bytes32 ilk = cdpManager.ilks(cdp);
            JoinAdapter(joinAdapters[ilk]).exit(address(this), dink);

            address gem = gems[ilk];

            ERC20(gem).approve(address(iDai), dink);

            iDai.borrowTokenFromDeposit(
                borrowAmounts[i],
                leverageAmount,
                initialLoanDuration,
                collateralDink,
                _borrower,
                address(this),
                gem,
                loanData
            );

            uint excess = dink - collateralDink;
            if (excess > 0) {
                LoanTokenInterface iCollateral = LoanTokenInterface(tokens[ilk]);
                ERC20(gem).approve(address(iCollateral), excess);
                iCollateral.mint(_borrower, excess);
            }
        }

        // repaying flash borrow
        ERC20(dai).transfer(address(iDai), loanAmount);
    }

    function setAddresses(address[] memory _joinAdapters, address[] memory iTokens) public onlyOwner
    {
        for (uint i = 0; i < _joinAdapters.length; i++) {
            JoinAdapter ja = JoinAdapter(_joinAdapters[i]);
            bytes32 ilk = ja.ilk();
            joinAdapters[ilk] = address(ja);
            gems[ilk] = ja.gem();

            LoanTokenInterface iToken = LoanTokenInterface(iTokens[i]);
            requireThat(iToken.loanTokenAddress() == gems[ilk], "Incompatible join adapter", i);

            tokens[ilk] = address(iToken);
            emit NewAddresses(ilk, address(ja), address(iToken));
        }
    }
}
