//
//  Instrument+CoreDataClass.swift
//  Pecunia
//
//  Created by Frank Emminghaus on 25.05.21.
//  Copyright © 2021 Frank Emminghaus. All rights reserved.
//
//

import Foundation
import CoreData
import HBCI4Swift

@objc(Instrument)
public class Instrument: NSManagedObject {
    public class func createWithHBCIData(instrument: HBCICustodyAccountBalance.FinancialInstrument, context:NSManagedObjectContext) -> Instrument {
        let result = NSEntityDescription.insertNewObject(forEntityName: "Instrument", into: context) as! Instrument;
        result.isin = instrument.isin;
        result.accruedInterestValue = instrument.accruedInterestValue?.value;
        result.accruedInterestValueCurrency = instrument.accruedInterestValue?.currency;
        result.currentPrice = instrument.currentPrice?.value;
        result.currentPriceCurrency = instrument.currentPrice?.currency;
        result.depotCurrency = instrument.depotCurrency;
        result.depotValue = instrument.depotValue?.value;
        result.depotValueCurrency = instrument.depotValue?.currency;
        result.interestRate = instrument.interestRate;
        result.name = instrument.name;
        result.priceDate = instrument.priceDate;
        result.priceLocation = instrument.priceLocation;
        result.startPrice = instrument.startPrice?.value;
        result.startPriceCurrency = instrument.startPrice?.currency;
        result.totalNumber = instrument.totalNumber;
        result.totalNumberType = instrument.numberType.rawValue;
        result.wkn = instrument.wkn;
        
        for balance in instrument.balances {
            let bal = InstrumentBalance.createWithHBCIData(balance: balance, context: context);
            result.addToBalances(bal);
        }
        return result;
    }

}
