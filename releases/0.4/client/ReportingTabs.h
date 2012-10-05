//
//  ReportingTabs.h
//  Pecunia
//
//  Created by Frank Emminghaus on 11.11.10.
//  Copyright 2010 Frank Emminghaus. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "BankingController.h"

@interface BankingController (ReportingTabs) 

-(IBAction)catPeriodView: (id)sender;
-(IBAction)categoryRep: (id)sender;
-(IBAction)catHistoryView: (id)sender;
-(IBAction)accountsRep: (id)sender;
-(IBAction)standingOrders: (id)sender;

@end
