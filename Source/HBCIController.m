//
//  HBCIController.m
//  Pecunia
//
//  Created by Frank Emminghaus on 24.07.11.
//  Copyright 2011 Frank Emminghaus. All rights reserved.
//

#import "HBCIController.h"

#import "BankInfo.h"
#import "PecuniaError.h"
#import "BankQueryResult.h"
#import "BankStatement.h"
#import "BankAccount.h"
#import "Transfer.h"
#import "MOAssistant.h"
#import "TransferResult.h"
#import "BankingController.h"
#import "WorkerThread.h"
#import "User.h"
#import "BankUser.h"
#import "Account.h"
#import "StandingOrder.h"
#import "HBCIBridge.h"
#import "Account.h"
#import "TransactionLimits.h"
#import "Country.h"
#import "ShortDate.h"
#import "BankParameter.h"
#import "ProgressWindowController.h"
#import "CustomerMessage.h"
#import "MessageLog.h"
#import "BankSetupInfo.h"
#import "TanMediaList.h"
#import "StatusBarController.h"
#import "Keychain.h"
#import "SigningOptionsController.h"
#import "SigningOption.h"
#import "CallbackHandler.h"
#import "SupportedTransactionInfo.h"

@implementation HBCIController

-(id)init
{
    self = [super init ];
    if(self == nil) return nil;
    
    bridge = [[HBCIBridge alloc ] init ];
    [bridge startup ];
    
    bankInfo = [[NSMutableDictionary alloc ] initWithCapacity: 10];
    countries = [[NSMutableDictionary alloc ] initWithCapacity: 50];
    [self readCountryInfos ]; 
    progressController = [[ProgressWindowController alloc ] init ];
    return self;
}

-(void)startProgress
{
    [progressController start ];
}

-(void)stopProgress
{
    [progressController stop ];
}


-(void)readCountryInfos
{
    NSError *error = nil;
    
    NSString *path = [[NSBundle mainBundle ] pathForResource: @"CountryInfo" ofType: @"txt" ];
    NSString *data = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error ];
    if (error) {
        NSAlert *alert = [NSAlert alertWithError:error];
		[alert runModal];
        return;
    }
    NSArray *lines = [data componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet ] ];
    NSString *line;
    for(line in lines) {
        NSArray *infos = [line componentsSeparatedByString: @";" ];
        Country *country = [[Country alloc ] init ];
        country.code = [infos objectAtIndex: 2 ];
        country.name = [infos objectAtIndex:0 ];
        country.currency = [infos objectAtIndex:3 ];
        [countries setObject:country forKey:country.code ];
    }
}

NSString *escapeSpecial(NSString *s)
{
    NSCharacterSet *cs = [NSCharacterSet characterSetWithCharactersInString:@"&<>'" ];
    NSRange range = [s rangeOfCharacterFromSet:cs ];
    if (range.location == NSNotFound) return s;
    NSString *res = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;" ];
    res = [res stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;" ];
    res = [res stringByReplacingOccurrencesOfString:@">" withString:@"&gt;" ];
    res = [res stringByReplacingOccurrencesOfString:@"'" withString:@"&apos;" ];
    return res;
}

-(NSDictionary*)countries
{
    return countries;
}

-(NSArray*)supportedVersions
{
    NSMutableArray *versions = [NSMutableArray arrayWithCapacity:2 ];
    [versions addObject:@"220" ];
    [versions addObject:@"300" ];
    return versions;
}

-(void)appendTag:(NSString*)tag withValue:(NSString*)val to:(NSMutableString*)cmd
{
    if (val == nil) return;
    NSString *s = escapeSpecial(val);
    if(val) [cmd appendFormat:@"<%@>%@</%@>", tag, s, tag ];
}

-(PecuniaError*)initalizeHBCI
{
    PecuniaError *error=nil;
    NSString *ppDir = [[MOAssistant assistant] passportDirectory ];
    NSString *bundlePath = [[NSBundle mainBundle ] bundlePath ];
    NSString *libPath = [bundlePath stringByAppendingString:@"/Contents/" ];
    
    NSMutableString *cmd = [NSMutableString stringWithString: @"<command name=\"init\">"];
    [self appendTag: @"passportPath" withValue: ppDir to: cmd ];
    [self appendTag: @"path" withValue: ppDir to: cmd ];
    [self appendTag: @"ddvLibPath" withValue: libPath to: cmd ];
    [cmd appendString: @"</command>" ];

    [bridge syncCommand: cmd error: &error ];
    return error;
}

-(BankInfo*)infoForBankCode: (NSString*)bankCode inCountry:(NSString*)country
{
    PecuniaError *error=nil;
    
    BankInfo *info = [bankInfo objectForKey: bankCode ];
    if(info == nil) {
        NSString *cmd = [NSString stringWithFormat: @"<command name=\"getBankInfo\"><bankCode>%@</bankCode></command>", bankCode ];
        info = [bridge syncCommand: cmd error: &error ];
        if(error == nil && info) [bankInfo setObject: info forKey: bankCode ]; else return nil;
    }
    return info;
}

-(BankParameter*)getBankParameterForUser:(BankUser*)user
{
    PecuniaError *error=nil;
    BankParameter *bp=nil;
    
    if ([self registerBankUser:user error:&error]) {
        NSString *cmd = [NSString stringWithFormat: @"<command name=\"getBankParameterRaw\"><bankCode>%@</bankCode><userId>%@</userId></command>", user.bankCode, user.userId ];
        bp = [bridge syncCommand:cmd error:&error ];
    }
    if (error) {
        [error alertPanel ];
        return nil;
    }
    return bp;
}

-(BankSetupInfo*)getBankSetupInfo:(NSString*)bankCode
{
    PecuniaError *error=nil;
    
    NSString *cmd = [NSString stringWithFormat: @"<command name=\"getInitialBPD\"><bankCode>%@</bankCode></command>", bankCode ];
    BankSetupInfo *info = [bridge syncCommand:cmd error:&error ];
    if (error) {
        [error alertPanel ];
        return nil;
    }
    return info;
}


-(NSString*)bankNameForCode:(NSString*)bankCode inCountry:(NSString*)country
{
    BankInfo *info = [self infoForBankCode: bankCode inCountry:country ];
    if(info==nil || info.name == nil) return NSLocalizedString(@"unknown",@"- unknown -");
    return info.name;
}

-(NSString*)bankNameForBIC:(NSString*)bic inCountry:(NSString*)country
{
    // is not supported
    return @"";
}

-(NSArray*)getAccountsForUser:(BankUser*)user
{
    PecuniaError *error=nil;
    NSArray *accs=nil;
    if ([self registerBankUser:user error:&error]) {
        NSString *cmd = [NSString stringWithFormat: @"<command name=\"getAccounts\"><bankCode>%@</bankCode><userId>%@</userId></command>", user.bankCode, user.userId ];
        accs = [bridge syncCommand: cmd error:&error ];
    }
    if (error != nil) {
        [error alertPanel ];
        return nil;
    }
    return accs;
}

-(PecuniaError*)addAccount: (BankAccount*)account forUser: (BankUser*)user
{
    account.customerId = user.customerId;
    return [self setAccounts:[NSArray arrayWithObject:account ] ];
}

-(PecuniaError*)setAccounts:(NSArray*)bankAccounts
{
    PecuniaError	*error = nil;
    
    BankAccount	*acc;
    for(acc in bankAccounts) {
        NSMutableString	*cmd = [NSMutableString stringWithFormat: @"<command name=\"setAccount\">" ];
        [self appendTag: @"bankCode" withValue: acc.bankCode to: cmd ];
        [self appendTag: @"accountNumber" withValue: acc.accountNumber to: cmd ];
        [self appendTag: @"subNumber" withValue: acc.accountSuffix to:cmd ];
        [self appendTag: @"country" withValue: [acc.country uppercaseString] to: cmd ];
        [self appendTag: @"iban" withValue: acc.iban to: cmd ];
        [self appendTag: @"bic" withValue: acc.bic to: cmd ];
        [self appendTag: @"ownerName" withValue: acc.owner to: cmd ];
        [self appendTag: @"name" withValue: acc.name to: cmd ];
        [self appendTag: @"customerId" withValue: acc.customerId to: cmd ];
        [self appendTag: @"userId" withValue: acc.userId to: cmd ];
        [self appendTag: @"currency" withValue: acc.currency to: cmd ];
        [cmd appendString: @"</command>" ];
        [bridge syncCommand: cmd error: &error ];
        if(error != nil) return error;
    }
    return nil;
}

-(PecuniaError*)changeAccount:(BankAccount*)account
{
    PecuniaError	*error = nil;
    
    NSMutableString	*cmd = [NSMutableString stringWithFormat: @"<command name=\"changeAccount\">" ];
    [self appendTag: @"bankCode" withValue: account.bankCode to: cmd ];
    [self appendTag: @"accountNumber" withValue: account.accountNumber to: cmd ];
    [self appendTag: @"subNumber" withValue: account.accountSuffix to:cmd ];
    [self appendTag: @"iban" withValue: account.iban to: cmd ];
    [self appendTag: @"bic" withValue: account.bic to: cmd ];
    [self appendTag: @"ownerName" withValue: account.owner to: cmd ];
    [self appendTag: @"name" withValue: account.name to: cmd ];
    [self appendTag: @"customerId" withValue: account.customerId to: cmd ];
    [self appendTag: @"userId" withValue: account.userId to: cmd ];
    [cmd appendString: @"</command>" ];
    [bridge syncCommand: cmd error: &error ];
    if(error != nil) return error;
    
    return nil;	
}


-(NSString*)jobNameForType: (TransferType)tt
{
    switch(tt) {
        case TransferTypeStandard: return @"Ueb"; break;
        case TransferTypeDated: return @"TermUeb"; break;
        case TransferTypeInternal: return @"Umb"; break;
        case TransferTypeEU: return @"UebForeign"; break;
        case TransferTypeDebit: return @"Last"; break;
        case TransferTypeSEPA: return @"UebSEPA"; break;
        case TransferTypeCollectiveCredit: return @"MultiUeb"; break;
        default:
            return nil;
    };
}

-(BOOL)isJobSupported:(NSString*)jobName forAccount:(BankAccount*)account
{
    PecuniaError *error=nil;
    if(account == nil) return NO;
    
    BankUser *user = [account defaultBankUser ];
    if (user == nil) return NO;
    if ([self registerBankUser:user error:&error ] == NO) {
        if (error) {
            [error logMessage ];
            return NO;
        }
        return NO;
    }
    
    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"isJobSupported\">" ];
    [self appendTag: @"bankCode" withValue: account.bankCode to: cmd ];
    [self appendTag: @"userId" withValue: account.userId to: cmd ];
    [self appendTag: @"jobName" withValue: jobName to: cmd ];
    [self appendTag: @"accountNumber" withValue: account.accountNumber to: cmd ];
    [self appendTag: @"subNumber" withValue: account.accountSuffix to:cmd ];
    [cmd appendString: @"</command>" ];
    NSNumber *result = [bridge syncCommand: cmd error: &error ];
    if(result) return [result boolValue ]; else return NO;
}

-(BOOL)isTransferSupported:(TransferType)tt forAccount:(BankAccount*)account
{
    NSString *jobName = [self jobNameForType: tt ];
    return [self isJobSupported: jobName forAccount: account ];
}

-(BOOL)isStandingOrderSupportedForAccount:(BankAccount*)account
{
    return [self isJobSupported:@"DauerNew" forAccount:account ];
}

-(NSDictionary*)getRestrictionsForJob:(NSString*)jobname account:(BankAccount*)account
{
    NSDictionary *result;
    PecuniaError *error=nil;
    if(account == nil) return nil;
    
    BankUser *user = [account defaultBankUser ];
    if (user == nil) return nil;
    
    if ([self registerBankUser:user error:&error] == NO) {
        if (error) {
            [error alertPanel ];
        }
        return nil;
    }
    
    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"getJobRestrictions\">" ];
    [self appendTag: @"bankCode" withValue: account.bankCode to: cmd ];
    [self appendTag: @"userId" withValue: account.userId to: cmd ];
    [self appendTag: @"jobName" withValue: jobname to: cmd ];
    [cmd appendString: @"</command>" ];
    result = [bridge syncCommand: cmd error: &error ];
    return result;
}

-(NSArray*)allowedCountriesForAccount:(BankAccount*)account
{
    NSMutableArray *res = [NSMutableArray arrayWithCapacity:20 ];
    NSDictionary *restr = [self getRestrictionsForJob:@"UebForeign" account:account ];
    NSArray *countryInfo = [restr valueForKey: @"countryInfos" ];
    NSString *s;
    
    // get texts for allowed countries - build up PopUpButton data
    for(s in countryInfo) {
        NSArray *comps = [s componentsSeparatedByString: @";" ];
        Country  *country = [countries valueForKey:[comps objectAtIndex:0 ] ];
        if(country != nil) [res addObject:country ];
    }
    if ([res count ] == 0) {
        return [countries allValues ];
    }
    
    return res;
}

-(TransactionLimits*)limitsForType:(TransferType)tt account:(BankAccount*)account country:(NSString*)ctry
{
    TransactionLimits *limits = [[TransactionLimits alloc ] init ];
    NSString *jobName = [self jobNameForType: tt ];
    NSDictionary *restr = [self getRestrictionsForJob:jobName account:account ];
    if (restr) {
        limits.allowedTextKeys = [restr valueForKey:@"textKeys" ];
        
        limits.maxLenPurpose = 27;
        limits.maxLenRemoteName = 27;
        limits.maxLinesRemoteName = 2;
        NSString *s = [restr valueForKey:@"maxusage" ];
        if (s) {
            limits.maxLinesPurpose = [s intValue ];
        } else {
            limits.maxLinesPurpose = 2;
        }
        s = [restr valueForKey:@"minpreptime" ];
        if (s) {
            limits.minSetupTime = [s intValue ];
        }
        s = [restr valueForKey:@"maxpreptime" ];
        if (s) {
            limits.maxSetupTime = [s intValue ];
        }
    }
    return limits;
}

-(TransactionLimits*)standingOrderLimitsForAccount:(BankAccount*)account action:(StandingOrderAction)action
{
    TransactionLimits *limits = [[TransactionLimits alloc ] init ];
    NSString *jobName = nil;
    switch (action) {
        case stord_change: jobName = @"DauerEdit"; break;
        case stord_create: jobName = @"DauerNew"; break;
        case stord_delete: jobName = @"DauerDel"; break;
    }
    if (jobName == nil) return nil;
    NSDictionary *restr = [self getRestrictionsForJob:jobName account:account ];
    if (restr) {
        limits.allowedTextKeys = [restr valueForKey:@"textKeys" ];
        
        limits.maxLenPurpose = 27;
        limits.maxLenRemoteName = 27;
        limits.maxLinesRemoteName = 2;
        NSString *s = [restr valueForKey:@"maxusage" ];
        if (s) {
            limits.maxLinesPurpose = [s intValue ];
        } else {
            limits.maxLinesPurpose = 2;
        }
        s = [restr valueForKey:@"minpretime" ];
        if (s) {
            limits.minSetupTime = [s intValue ];
        }
        s = [restr valueForKey:@"maxpretime" ];
        if (s) {
            limits.maxSetupTime = [s intValue ];
        }
        
        s = [restr valueForKey:@"dayspermonth" ];
        if (s) {
            NSMutableArray *execDays = [NSMutableArray arrayWithCapacity:30 ];
            while ([s length ] > 0) {
                [execDays addObject: [s substringToIndex:2 ] ];
                s = [s substringFromIndex:2 ];
            }
            limits.execDaysMonth = execDays;
        }
        
        s = [restr valueForKey:@"daysperweek" ];
        if (s) {
            NSMutableArray *execDays = [NSMutableArray arrayWithCapacity:7 ];
            while ([s length ] > 0) {
                [execDays addObject: [s substringToIndex:1 ] ];
                s = [s substringFromIndex:1 ];
            }
            limits.execDaysWeek = execDays;
        }
        
        s = [restr valueForKey:@"turnusmonths" ];
        if (s) {
            NSMutableArray *cycles = [NSMutableArray arrayWithCapacity:12 ];
            while ([s length ] > 0) {
                [cycles addObject: [s substringToIndex:2 ] ];
                s = [s substringFromIndex:2 ];
            }
            limits.monthCycles = cycles;
        }
        
        s = [restr valueForKey:@"turnusweeks" ];
        if (s) {
            NSMutableArray *cycles = [NSMutableArray arrayWithCapacity:12 ];
            while ([s length ] > 0) {
                [cycles addObject: [s substringToIndex:2 ] ];
                s = [s substringFromIndex:2 ];
            }
            limits.weekCycles = cycles;
        }
        
        limits.allowMonthly = YES;
        if (limits.execDaysWeek == nil || limits.weekCycles == nil) limits.allowWeekly = NO; else limits.allowWeekly = YES;
        
        if (action == stord_change) {
            s = [restr valueForKey:@"recktoeditable" ];
            limits.allowChangeRemoteAccount = NO;
            if (s) {
                if ([s isEqualToString:@"J" ]) limits.allowChangeRemoteAccount = YES;
            }
            s = [restr valueForKey:@"recnameeditable" ];
            limits.allowChangeRemoteName = NO;
            if (s) {
                if ([s isEqualToString:@"J" ]) limits.allowChangeRemoteName = YES;
            }
            s = [restr valueForKey:@"usageeditable" ];
            limits.allowChangePurpose = NO;
            if (s) {
                if ([s isEqualToString:@"J" ]) limits.allowChangePurpose = YES;
            }
            s = [restr valueForKey:@"firstexeceditable" ];
            limits.allowChangeFirstExecDate = NO;
            if (s) {
                if ([s isEqualToString:@"J" ]) limits.allowChangeFirstExecDate = YES;
            }
            s = [restr valueForKey:@"lastexeceditable" ];
            limits.allowChangeLastExecDate = NO;
            if (s) {
                if ([s isEqualToString:@"J" ]) limits.allowChangeLastExecDate = YES;
            }
            s = [restr valueForKey:@"timeuniteditable" ];
            limits.allowChangePeriod = NO;
            if (s) {
                if ([s isEqualToString:@"J" ]) limits.allowChangePeriod = YES;
            }
            s = [restr valueForKey:@"turnuseditable" ];
            limits.allowChangeCycle = NO;
            if (s) {
                if ([s isEqualToString:@"J" ]) limits.allowChangeCycle = YES;
            }
            s = [restr valueForKey:@"execdayeditable" ];
            limits.allowChangeExecDay = NO;
            if (s) {
                if ([s isEqualToString:@"J" ]) limits.allowChangeExecDay = YES;
            }
            s = [restr valueForKey:@"valueeditable" ];
            limits.allowChangeValue = NO;
            if (s) {
                if ([s isEqualToString:@"J" ]) limits.allowChangeValue = YES;
            }
        } else {
            limits.allowChangeRemoteName = YES;
            limits.allowChangeRemoteAccount = YES;
            limits.allowChangePurpose = YES;
            limits.allowChangeValue = YES;
            limits.allowChangePeriod = YES;
            limits.allowChangeLastExecDate = YES;
            limits.allowChangeFirstExecDate = YES;
            limits.allowChangeExecDay = YES;
            limits.allowChangeCycle = YES;
        }
        
        
    }
    return limits;
}

-(PecuniaError*)sendCollectiveTransfer:(NSArray*)transfers
{
    PecuniaError *err = nil;
    Transfer *transfer;

    if ([transfers count] == 0) return nil;
    
    // Prüfen ob alle Überweisungen das gleiche Konto betreffen
    transfer = [transfers lastObject ];
    for(Transfer *transf in transfers) {
        if (transfer.account != transf.account) {
            return [PecuniaError errorWithMessage:NSLocalizedString(@"424",@"") title:NSLocalizedString(@"AP423",@"") ];
            /*
            NSRunAlertPanel(NSLocalizedString(@"423", @""), 
                            NSLocalizedString(@"424",@""), 
                            NSLocalizedString(@"ok",@""));
            return;
            */
        }
    }

    SigningOption *option = [self signingOptionForAccount:transfer.account ];
    if (option == nil) {
        return nil;
    }
    [CallbackHandler handler ].currentSigningOption = option;
    
    // Registriere gewählten User
    BankUser *user = [BankUser userWithId:option.userId bankCode:transfer.account.bankCode ];
    if (user == nil) {
        return [PecuniaError errorWithMessage: [NSString stringWithFormat: NSLocalizedString(@"424",@""), option.userId ] title:NSLocalizedString(@"AP355",@"")  ];
    }
    
    if ([self registerBankUser:user error:&err] == NO) return err;
    if ([user.tanMediaFetched boolValue] == NO) [self updateTanMediaForUser:user ];
    
    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"sendCollectiveTransfer\">" ];
    [self appendTag: @"bankCode" withValue: transfer.account.bankCode to: cmd];
    [self appendTag: @"accountNumber" withValue: transfer.account.accountNumber to: cmd];
    [self appendTag: @"subNumber" withValue: transfer.account.accountSuffix to: cmd];
    [self appendTag: @"customerId" withValue: transfer.account.customerId to: cmd];
    [self appendTag: @"userId" withValue: transfer.account.userId to: cmd];
    [cmd appendString:@"<transfers type=\"list\">" ];
    for(transfer in transfers) {
        [cmd appendString: @"<transfer>"];
        [self appendTag: @"remoteAccount" withValue: transfer.remoteAccount to: cmd];
        [self appendTag: @"remoteBankCode" withValue: transfer.remoteBankCode to: cmd];
        [self appendTag: @"remoteName" withValue: transfer.remoteName to: cmd];
        [self appendTag: @"purpose1" withValue: transfer.purpose1 to: cmd];
        [self appendTag: @"purpose2" withValue: transfer.purpose2 to: cmd];
        [self appendTag: @"purpose3" withValue: transfer.purpose3 to: cmd];
        [self appendTag: @"purpose4" withValue: transfer.purpose4 to: cmd];
        [self appendTag: @"currency" withValue: transfer.currency to: cmd];
        [self appendTag: @"remoteBIC" withValue: transfer.remoteBIC to: cmd];
        [self appendTag: @"remoteIBAN" withValue: transfer.remoteIBAN to: cmd];
        [self appendTag: @"remoteCountry" withValue: transfer.remoteCountry == nil ? @"DE" : [transfer.remoteCountry uppercaseString] to: cmd];
        
        NSDecimalNumber *val = [transfer.value decimalNumberByMultiplyingByPowerOf10: 2];
        [self appendTag: @"value" withValue: [val stringValue] to: cmd];
        [cmd appendString: @"</transfer>"];
    }
    
    [cmd appendString: @"</transfers></command>"];
    
    [self startProgress ];
    NSNumber *isOk = [bridge syncCommand: cmd error: &err];
    [self stopProgress ];
    if (err == nil && [isOk boolValue ] == YES) {
        for(transfer in transfers) transfer.isSent = [NSNumber numberWithBool:YES ];
    }
    return err;
}

/**
 * Sends out the given transfer by grouping them by bank and issuing one command per bank.
 * TODO: If supported by the bank grouped transfers should use consolidated transfers instead individual ones.
 */
-(BOOL)sendTransfers:(NSArray*)transfers 
{
    PecuniaError *err = nil;
    Transfer *transfer;
    NSManagedObjectContext *context = MOAssistant.assistant.context;
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] initWithDateFormat: @"%Y-%m-%d" allowNaturalLanguage: NO];
    NSMutableDictionary *accountTransferRegister = [NSMutableDictionary dictionaryWithCapacity: 10];
    
    // Group transfers by BankAccount
    for (transfer in transfers) {
        BankAccount *account = transfer.account;
        NSMutableArray *accountTransfers = [accountTransferRegister objectForKey: account];
        if (accountTransfers == nil) {
            accountTransfers = [NSMutableArray arrayWithCapacity: 10];
            [accountTransferRegister setObject: accountTransfers forKey: account];
        }
        [accountTransfers addObject: transfer];
    }
    
    // Now go for each bank.
    BOOL allSent = YES;
    
    for (BankAccount *account in [accountTransferRegister allKeys]) {
        SigningOption *option = [self signingOptionForAccount:account ];
        if (option == nil) {
            continue;
        }
        [CallbackHandler handler ].currentSigningOption = option;
        
        // Registriere gewählten User
        BankUser *user = [BankUser userWithId:option.userId bankCode:account.bankCode ];
        if (user == nil) {
            continue;
        }
        if ([self registerBankUser:user error:&err] == NO) {
            if (err) {
                [err alertPanel ];
            }
            continue;
        }
        if ([user.tanMediaFetched boolValue] == NO) [self updateTanMediaForUser:user ];
        
        NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"sendTransfers\"><transfers type=\"list\">" ];
        for (transfer in [accountTransferRegister objectForKey: account]) {
            [cmd appendString: @"<transfer>"];
            [self appendTag: @"bankCode" withValue: transfer.account.bankCode to: cmd];
            [self appendTag: @"accountNumber" withValue: transfer.account.accountNumber to: cmd];
            [self appendTag: @"subNumber" withValue: transfer.account.accountSuffix to: cmd];
            [self appendTag: @"customerId" withValue: transfer.account.customerId to: cmd];
            [self appendTag: @"userId" withValue: transfer.account.userId to: cmd];
            [self appendTag: @"remoteAccount" withValue: transfer.remoteAccount to: cmd];
            [self appendTag: @"remoteBankCode" withValue: transfer.remoteBankCode to: cmd];
            [self appendTag: @"remoteName" withValue: transfer.remoteName to: cmd];
            [self appendTag: @"purpose1" withValue: transfer.purpose1 to: cmd];
            [self appendTag: @"purpose2" withValue: transfer.purpose2 to: cmd];
            [self appendTag: @"purpose3" withValue: transfer.purpose3 to: cmd];
            [self appendTag: @"purpose4" withValue: transfer.purpose4 to: cmd];
            [self appendTag: @"currency" withValue: transfer.currency to: cmd];
            [self appendTag: @"remoteBIC" withValue: transfer.remoteBIC to: cmd];
            [self appendTag: @"remoteIBAN" withValue: transfer.remoteIBAN to: cmd];
            [self appendTag: @"remoteCountry" withValue: transfer.remoteCountry == nil ? @"DE" : [transfer.remoteCountry uppercaseString] to: cmd];
            if([transfer.type intValue] == TransferTypeDated) {
                NSString *fromString = [dateFormatter stringFromDate: transfer.valutaDate];
                [self appendTag: @"valutaDate" withValue: fromString to: cmd];
            }
            TransferType tt = [transfer.type intValue];
            NSString *type;
            switch(tt) {
                case TransferTypeStandard:
                    type = @"standard";
                    break;
                case TransferTypeDated:
                    type = @"dated";
                    break;
                case TransferTypeInternal:
                    type = @"internal";
                    break;
                case TransferTypeDebit:
                    type = @"last";
                    break;
                case TransferTypeSEPA:
                    type = @"sepa";
                    break;
                case TransferTypeEU:	
                    type = @"foreign";
                    [self appendTag:@"chargeTo" withValue: [transfer.chargedBy description]  to: cmd];
                    break;
                case TransferTypeCollectiveCredit:
                case TransferTypeCollectiveDebit:
                    [[MessageLog log ] addMessage:@"Collective transfer must be sent with 'sendCollectiveTransfer'" withLevel:LogLevel_Error];
                    continue;
                    break;
            }
            
            [self appendTag: @"type" withValue: type to: cmd];
            NSDecimalNumber *val = [transfer.value decimalNumberByMultiplyingByPowerOf10: 2];
            [self appendTag: @"value" withValue: [val stringValue] to: cmd];
            
            NSURL *uri = [[transfer objectID] URIRepresentation];
            [self appendTag: @"transferId" withValue: [uri absoluteString] to: cmd];
            [cmd appendString: @"</transfer>"];
        }
        [cmd appendString: @"</transfers></command>"];
        
        [self startProgress];
        NSArray *resultList = [bridge syncCommand: cmd error: &err];
        [self stopProgress];
        if (err) {
            [err logMessage ];
        }
        
        for (TransferResult *result in resultList) {
            NSURL *uri = [NSURL URLWithString:result.transferId];
            NSManagedObjectID *moID = [[context persistentStoreCoordinator] managedObjectIDForURIRepresentation: uri];
            Transfer *transfer = (Transfer*)[context objectWithID: moID];
            if (result.isOk) {
                transfer.isSent = [NSNumber numberWithBool: YES];
            } else {
                allSent = NO;
            }
        }
    }
    return allSent;
}

-(BOOL)checkAccount:(NSString*)accountNumber forBank:(NSString*)bankCode inCountry: (NSString*)country
{
    PecuniaError *error=nil;
    
    if(bankCode == nil || accountNumber == nil) return YES;
    NSString *cmd = [NSString stringWithFormat: @"<command name=\"checkAccount\"><bankCode>%@</bankCode><accountNumber>%@</accountNumber></command>", bankCode, accountNumber ];
    NSNumber *result = [bridge syncCommand: cmd error: &error ];
    if (error) {
        // Bei Fehlern sollte die Prüfung nicht die Buchung verhindern
        [[MessageLog log ] addMessage:[NSString stringWithFormat:@"Error checking account %@, bankCode %@", accountNumber, bankCode ] withLevel:LogLevel_Warning ];
        return YES;
    }
    if(result) return [result boolValue ]; else return NO;
}

-(BOOL)checkIBAN:(NSString*)iban
{
    PecuniaError *error=nil;
    
    if(iban == nil) return YES;
    NSString *cmd = [NSString stringWithFormat: @"<command name=\"checkAccount\"><iban>%@</iban></command>", iban ];
    NSNumber *result = [bridge syncCommand: cmd error: &error ];
    if (error) {
        // Bei Fehlern sollte die Prüfung nicht die Buchung verhindern
        [[MessageLog log ] addMessage:[NSString stringWithFormat:@"Error checking iban %@", iban ] withLevel:LogLevel_Warning ];
        return YES;
    }
    if(result) return [result boolValue ]; else return NO;
}

-(PecuniaError*)addBankUser:(BankUser*)user
{
    PecuniaError *error=nil;
    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"addUser\">" ];

    [self appendTag: @"name" withValue: user.name to: cmd ];
    [self appendTag: @"bankCode" withValue: user.bankCode to: cmd ];
    [self appendTag: @"customerId" withValue: user.customerId to: cmd ];
    [self appendTag: @"userId" withValue: user.userId to: cmd ];
    [self appendTag: @"version" withValue: user.hbciVersion to: cmd ];
    
    SecurityMethod secMethod = [user.secMethod intValue ];
    if (secMethod == SecMethod_PinTan) {
        [self appendTag: @"host" withValue: [user.bankURL stringByReplacingOccurrencesOfString: @"https://" withString:@"" ] to: cmd ];
        [self appendTag: @"port" withValue: @"443" to: cmd ];
        [self appendTag: @"passportType" withValue: @"PinTan" to: cmd ];
        if([user.noBase64 boolValue] == NO) [self appendTag: @"filter" withValue: @"Base64" to: cmd ];
    }
    
    if (secMethod == SecMethod_DDV) {
        [self appendTag: @"ddvReaderIdx" withValue: [user.ddvReaderIdx stringValue ] to: cmd ];
        [self appendTag: @"ddvPortIdx" withValue: [user.ddvPortIdx stringValue ] to: cmd ];
        [self appendTag: @"passportType" withValue: @"DDV" to: cmd ];
        [self appendTag: @"host" withValue: user.bankURL to: cmd ];
    }
    
    [cmd appendString: @"</command>" ];
    
    // create bank user at the bank
    User* usr = [bridge syncCommand: cmd error: &error ];
    if (error) {
        return error;
    }
    
    // update external user data
    if (secMethod == SecMethod_DDV) {
        user.bankCode = usr.bankCode;
        user.bankName = usr.bankName;
        user.customerId = usr.customerId;
        user.hbciVersion = usr.hbciVersion;
        user.country = usr.country;
        user.chipCardId = usr.chipCardId;
    }
    
    // Update user's accounts
    [self updateBankAccounts:usr.accounts forUser:user];
    
    // update supported transactions
    error = [self updateSupportedTransactionsForAccounts:usr.accounts user:user];
    if(error != nil) return error;    
    
    // also update TAN media and TAN methods
    if (secMethod == SecMethod_PinTan) {
        error = [self updateTanMethodsForUser:user ];
        if(error != nil) return error;
        error = [self updateTanMediaForUser:user ];
        if(error != nil) return error;
    }
    return nil;
}

-(BOOL)deleteBankUser:(BankUser*)user 
{
    PecuniaError *error=nil;
    
    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"deletePassport\">" ];
    [self appendTag: @"bankCode" withValue: user.bankCode to: cmd ];
    [self appendTag: @"userId" withValue: user.userId to: cmd ];

    SecurityMethod secMethod = [user.secMethod intValue ];
    if (secMethod == SecMethod_PinTan) {
        [self appendTag: @"passportType" withValue: @"PinTan" to: cmd ];
    } else {
        [self appendTag: @"passportType" withValue: @"DDV" to: cmd ];
        [self appendTag: @"chipCardId" withValue:user.chipCardId to:cmd ];
    }

    [cmd appendString: @"</command>" ];
        
    [bridge syncCommand: cmd error:&error ];
    if(error == nil) {
        NSString *s = [NSString stringWithFormat: @"PIN_%@_%@", user.bankCode, user.userId ];
        [Keychain deletePasswordForService:@"Pecunia PIN" account: s ];
    } else {
        [error alertPanel ];
        return NO;
    }
    return YES;
}

-(PecuniaError*)setLogLevel:(LogLevel)level
{
    PecuniaError *error=nil;
    NSMutableString	*cmd = [NSMutableString stringWithFormat:@"<command name=\"setLogLevel\"><logLevel>%d</logLevel></command>", level+1 ];
    [bridge syncCommand: cmd error: &error ];
    if (error != nil) return error;
    return nil;
}


-(void)getStatements:(NSArray*)resultList
{
    bankQueryResults = resultList;
    NSMutableString	*cmd = [NSMutableString stringWithFormat:@"<command name=\"getAllStatements\"><accinfolist type=\"list\">" ];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] initWithDateFormat:@"%Y-%m-%d" allowNaturalLanguage:NO];
    
    BankQueryResult *result;
    for(result in resultList) {
        // check if user is registered
        PecuniaError *error = nil;
        BankUser *user = [BankUser userWithId:result.userId bankCode:result.bankCode ];
        if (user == nil) continue;
        if ([self registerBankUser:user error:&error] == NO) {
            if (error) {
                [error alertPanel ];
            }
            continue;
        };
        
        [cmd appendFormat:@"<accinfo><bankCode>%@</bankCode><accountNumber>%@</accountNumber>", result.bankCode, result.accountNumber ];
        [self appendTag:@"subNumber" withValue:result.accountSubnumber to:cmd ];
        
        
        
        NSInteger maxStatDays = 0;
        if ([[NSUserDefaults standardUserDefaults ] boolForKey:@"limitStatsAge"]) {
            maxStatDays = [[NSUserDefaults standardUserDefaults ] integerForKey:@"maxStatDays" ];
            if (maxStatDays == 0) maxStatDays = 90;
        }
        
        if (result.account.latestTransferDate == nil && maxStatDays > 0) {
            result.account.latestTransferDate = [[NSDate alloc] initWithTimeInterval: -86400 * maxStatDays sinceDate: [NSDate date]];
        }
        
        if (result.account.latestTransferDate != nil) {
            NSString *fromString = nil;
            NSDate *fromDate = [[NSDate alloc ] initWithTimeInterval:-605000 sinceDate:result.account.latestTransferDate ];
            fromString = [dateFormatter stringFromDate:fromDate ];
            if (fromString) [cmd appendFormat:@"<fromDate>%@</fromDate>", fromString ];
        }
        [cmd appendFormat:@"<userId>%@</userId></accinfo>", result.userId ];
    }
    [cmd appendString:@"</accinfolist></command>" ];
    [self startProgress ];
    [bridge asyncCommand: cmd sender: self ];
}

-(void)asyncCommandCompletedWithResult:(id)result error:(PecuniaError*)err
{
    if(err == nil && result != nil) {
        BankQueryResult *res;
        
        for(res in result) {
            // find corresponding incoming structure
            BankQueryResult *iResult;
            for(iResult in bankQueryResults) {
				if([iResult.accountNumber isEqualToString: res.accountNumber ] && [iResult.bankCode isEqualToString: res.bankCode ] &&
                   ((iResult.accountSubnumber == nil && res.accountSubnumber == nil) || [iResult.accountSubnumber isEqualToString: res.accountSubnumber ])) break;
            }
            // saldo of the last statement is current saldo
            if ([res.statements count ] > 0) {
                BankStatement *stat = [res.statements objectAtIndex: [res.statements count ] - 1 ];
                iResult.balance = stat.saldo;
                /*				
                 // ensure order by refining posting date
                 int seconds;
                 NSDate *oldDate = [NSDate distantPast ];
                 for(stat in res.statements) {
                 if([stat.date compare: oldDate ] != NSOrderedSame) {
                 seconds = 0;
                 oldDate = stat.date;
                 } else seconds += 100;
                 if(seconds > 0) stat.date = [[[NSDate alloc ] initWithTimeInterval: seconds sinceDate: stat.date ] autorelease ];
                 }
                 */ 
                iResult.statements = res.statements;
            }
            if ([res.standingOrders count ] > 0) {
                iResult.standingOrders = res.standingOrders;
            }
        }
    }
    
    [self stopProgress ];
    
    if(err) {
        [err alertPanel ];
        NSNotification *notification = [NSNotification notificationWithName:PecuniaStatementsNotification object:nil ];
        [[NSNotificationCenter defaultCenter ] postNotification:notification ];
    } else {
        NSNotification *notification = [NSNotification notificationWithName:PecuniaStatementsNotification object:bankQueryResults ];
        [[NSNotificationCenter defaultCenter ] postNotification:notification ];
    }
}


-(void)getStandingOrders:(NSArray*)resultList
{
    bankQueryResults = resultList;
    NSMutableString	*cmd = [NSMutableString stringWithFormat:@"<command name=\"getAllStandingOrders\"><accinfolist type=\"list\">" ];
    
    for(BankQueryResult *result in resultList) {
        // check if user is registered
        PecuniaError *error = nil;
        BankUser *user = [BankUser userWithId:result.userId bankCode:result.bankCode ];
        if (user == nil) continue;
        if ([self registerBankUser:user error:&error] == NO) {
            if (error) {
                [error alertPanel ];
            }
            continue;
        };
        
        [cmd appendString:@"<accinfo>" ];
        [self appendTag: @"bankCode" withValue: result.bankCode to: cmd ];
        [self appendTag: @"accountNumber" withValue: result.accountNumber to: cmd ];
        [self appendTag: @"subNumber" withValue:result.accountSubnumber to:cmd ];
        [self appendTag: @"userId" withValue: result.userId to: cmd ];
        [cmd appendString:@"</accinfo>" ];
    }
    [cmd appendString:@"</accinfolist></command>" ];
    [self startProgress ];
    [bridge asyncCommand: cmd sender: self ];
}

-(void)prepareCommand:(NSMutableString*)cmd forStandingOrder:(StandingOrder*)stord
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] initWithDateFormat:@"%Y-%m-%d" allowNaturalLanguage:NO];
    
    [self appendTag: @"bankCode" withValue: stord.account.bankCode to: cmd ];
    [self appendTag: @"accountNumber" withValue: stord.account.accountNumber to: cmd ];
    [self appendTag: @"subNumber" withValue: stord.account.accountSuffix to:cmd ];
    [self appendTag: @"customerId" withValue: stord.account.customerId to: cmd ];
    [self appendTag: @"userId" withValue: stord.account.userId to: cmd ];
    [self appendTag: @"remoteAccount" withValue: stord.remoteAccount to: cmd ];
    [self appendTag: @"remoteBankCode" withValue: stord.remoteBankCode to: cmd ];
    [self appendTag: @"remoteName" withValue: stord.remoteName to: cmd ];
    [self appendTag: @"purpose1" withValue: stord.purpose1 to: cmd ];
    [self appendTag: @"purpose2" withValue: stord.purpose2 to: cmd ];
    [self appendTag: @"purpose3" withValue: stord.purpose3 to: cmd ];
    [self appendTag: @"purpose4" withValue: stord.purpose4 to: cmd ];
    [self appendTag: @"currency" withValue: stord.currency to: cmd ];
    [self appendTag: @"remoteCountry" withValue: @"DE" to: cmd ];
    NSDecimalNumber *val = [stord.value decimalNumberByMultiplyingByPowerOf10:2 ];
    [self appendTag: @"value" withValue: [val stringValue ] to: cmd ];
    
    [self appendTag: @"firstExecDate" withValue: [dateFormatter stringFromDate:stord.firstExecDate ] to: cmd ];
    if (stord.lastExecDate) {
        ShortDate *sDate = [ShortDate dateWithDate:stord.lastExecDate ];
        if (sDate.year < 2100) {
            [self appendTag: @"lastExecDate" withValue: [dateFormatter stringFromDate:stord.lastExecDate ] to: cmd ];
        }
    }
    
    // time unit
    switch ([stord.period intValue ]) {
        case stord_weekly: [self appendTag: @"timeUnit" withValue: @"W" to: cmd ]; break;
        default: [self appendTag: @"timeUnit" withValue: @"M" to: cmd ]; break;
    }
    
    [self appendTag: @"turnus" withValue: [stord.cycle stringValue ] to: cmd ];
    [self appendTag: @"executionDay" withValue: [stord.executionDay stringValue ] to: cmd ];
}

-(PecuniaError*)sendStandingOrders:(NSArray*)orders
{
    PecuniaError *err = nil;
    NSManagedObjectContext *context = [[MOAssistant assistant ] context ];
    
    NSMutableDictionary *accountTransferRegister = [NSMutableDictionary dictionaryWithCapacity: 10];
    
    // Group transfers by BankAccount
    for (StandingOrder *stord in orders) {
        BankAccount *account = stord.account;
        NSMutableArray *accountTransfers = [accountTransferRegister objectForKey: account];
        if (accountTransfers == nil) {
            accountTransfers = [NSMutableArray arrayWithCapacity: 10];
            [accountTransferRegister setObject: accountTransfers forKey: account];
        }
        [accountTransfers addObject: stord];
    }
    
    [self startProgress ];
    
    for (BankAccount *account in [accountTransferRegister allKeys]) {
        SigningOption *option = [self signingOptionForAccount:account ];
        if (option == nil) {
            continue;
        }
        [CallbackHandler handler ].currentSigningOption = option;
        
        // Registriere gewählten User
        BankUser *user = [BankUser userWithId:option.userId bankCode:account.bankCode ];
        if (user == nil) {
            continue;
        }
        if ([self registerBankUser:user error:&err] == NO) {
            if (err) {
                [err alertPanel ];
            }
            continue;
        };
        if ([user.tanMediaFetched boolValue] == NO) [self updateTanMediaForUser:user ];
        
    
        for(StandingOrder *stord in [accountTransferRegister objectForKey: account]) {
            
            // todo: don't send unchanged orders
            if ([stord.isChanged boolValue] == NO && [stord.toDelete boolValue ] == NO) continue;
            
            // don't send sent orders without ID
            if ([stord.isSent boolValue ] == YES && stord.orderKey == nil) continue;
            
            if (stord.orderKey == nil) {
                // create standing order
                NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"addStandingOrder\">" ];
                [self prepareCommand:cmd forStandingOrder:stord ];			
                [cmd appendString: @"</command>" ];
                
                NSDictionary *result = [bridge syncCommand: cmd error: &err  ];
                if (err) {
                    [err logMessage ];
                    [self stopProgress ];
                    return err;
                }
                stord.isSent = [result valueForKey:@"isOk" ];
                stord.orderKey = [result valueForKey:@"orderId" ];
                if (stord.isSent) {
                    stord.isChanged = [NSNumber numberWithBool:NO ];
                }
            } else if ([stord.toDelete boolValue ] == YES) {
                // delete standing order
                NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"deleteStandingOrder\">" ];
                [self prepareCommand:cmd forStandingOrder:stord ];
                if (stord.orderKey) {
                    [self appendTag:@"orderId" withValue:stord.orderKey to:cmd ];
                }
                [cmd appendString: @"</command>" ];
                
                NSNumber *result = [bridge syncCommand: cmd error: &err  ];
                if (err) {
                    [err logMessage ];
                    [self stopProgress ];
                    return err;
                }
                stord.isSent = result;
                if ([result boolValue ] == YES) {
                    [context deleteObject:stord ];
                }
            } else {
                // change standing order
                NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"changeStandingOrder\">" ];
                [self prepareCommand:cmd forStandingOrder:stord ];
                [self appendTag:@"orderId" withValue:stord.orderKey to:cmd ];			
                [cmd appendString: @"</command>" ];
                
                NSNumber *result = [bridge syncCommand: cmd error: &err  ];
                if (err) {
                    [err logMessage ];
                    [self stopProgress ];
                    return err;
                }
                stord.isSent = result;
                if ([result boolValue ] == YES) {
                    stord.isChanged = [NSNumber numberWithBool:NO ];
                }
            }		
        }
    }
    [self stopProgress ];
    return nil;
}

-(BankAccount*)getBankNodeWithAccount: (Account*)acc inAccounts: (NSMutableArray*)bankAccounts
{
    NSManagedObjectContext *context = [[MOAssistant assistant] context];
    BankAccount *bankNode = [BankAccount bankRootForCode: acc.bankCode];
    
    if(bankNode == nil) {
        Category *root = [Category bankRoot];
        if(root == nil) return nil;
        // create bank node
        bankNode = [NSEntityDescription insertNewObjectForEntityForName:@"BankAccount" inManagedObjectContext:context];
        bankNode.name = acc.bankName;
        bankNode.bankCode = acc.bankCode;
        bankNode.currency = acc.currency;
        bankNode.bic = acc.bic;
        bankNode.isBankAcc = [NSNumber numberWithBool: YES];
        bankNode.parent = root;
        if(bankAccounts) [bankAccounts addObject: bankNode];
    }
    return bankNode;
}

-(void)updateBankAccounts:(NSArray*)hbciAccounts forUser:(BankUser*)user
{
    NSManagedObjectContext *context = [[MOAssistant assistant] context];
    NSManagedObjectModel *model = [[MOAssistant assistant] model];
    NSError *error=nil;
    BOOL found;
    
    if (hbciAccounts == nil) {
        hbciAccounts = [self getAccountsForUser:user];
    }
    
    NSFetchRequest *request = [model fetchRequestTemplateForName:@"allBankAccounts"];
    NSArray *tmpAccounts = [context executeFetchRequest:request error:&error];
    if( error != nil || tmpAccounts == nil) {
        NSAlert *alert = [NSAlert alertWithError:error];
        [alert runModal];
        return;
    }
    NSMutableArray*	bankAccounts = [NSMutableArray arrayWithArray: tmpAccounts];
    
    for (Account *acc in hbciAccounts) {
        BankAccount *account;
        
        //lookup
        found = NO;
        for (account in bankAccounts) {
			if ([account.bankCode isEqual: acc.bankCode ] && [account.accountNumber isEqual: acc.accountNumber ] && 
                ((account.accountSuffix == nil && acc.subNumber == nil) || [account.accountSuffix isEqual: acc.subNumber ])) {
                found = YES;
                break;
            }
        }
        if (found) {
            // Update the user id if there is none assigned yet or if it differs.
            if (account.userId == nil || ![account.userId isEqualToString: acc.userId]) {
                account.userId = acc.userId;
                account.customerId = acc.customerId;
            }
            // ensure the user is linked to the account
            NSMutableSet *users = [account mutableSetValueForKey: @"users"];
            [users addObject: user];
            
            if (acc.bic != nil) {
                account.bic = acc.bic;
            }
            if (acc.iban != nil) {
                account.iban = acc.iban;
            }
            
        } else {
            // Account was not found: create it.
            BankAccount* bankRoot = [self getBankNodeWithAccount: acc inAccounts: bankAccounts];
            if(bankRoot == nil) return;
            BankAccount	*bankAccount = [NSEntityDescription insertNewObjectForEntityForName:@"BankAccount"
                                                                     inManagedObjectContext:context];
            
            bankAccount.accountNumber = acc.accountNumber;
            bankAccount.name = acc.name;
            bankAccount.bankCode = acc.bankCode;
            bankAccount.bankName = acc.bankName;
            bankAccount.currency = acc.currency;
            bankAccount.country = acc.country;
            bankAccount.owner = acc.ownerName;
            bankAccount.userId = acc.userId;
            bankAccount.customerId = acc.customerId;
            bankAccount.isBankAcc = [NSNumber numberWithBool: YES];
            bankAccount.accountSuffix = acc.subNumber;
            bankAccount.bic = acc.bic;
            bankAccount.iban = acc.iban;
            bankAccount.type = acc.type;
            //			bankAccount.uid = [NSNumber numberWithUnsignedInt: [acc uid]];
            //			bankAccount.type = [NSNumber numberWithUnsignedInt: [acc type]];
            
            // links
            bankAccount.parent = bankRoot;
            NSMutableSet *users = [bankAccount mutableSetValueForKey:@"users" ];
            [users addObject:user ];
        } 
    }
    // save updates
    if([context save: &error] == NO) {
        NSAlert *alert = [NSAlert alertWithError:error];
        [alert runModal];
        return;
    }
}

-(PecuniaError*)updateSupportedTransactionsForAccounts:(NSArray*)accounts user:(BankUser*)user
{
    NSError *error=nil;
    NSManagedObjectContext *context = [[MOAssistant assistant] context];
    NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"SupportedTransactionInfo" inManagedObjectContext:context];

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"user = %@", user];
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:entityDescription];
    [request setPredicate:predicate ];
    
    // remove existing
    NSArray *result = [context executeFetchRequest:request error:&error];
    if (error) {
        return [PecuniaError errorWithMessage:[error localizedDescription ] title:NSLocalizedString(@"AP182",@"")];
    }
    
    for(SupportedTransactionInfo *tinfo in result) {
        [context deleteObject:tinfo ];
    }
    
    for(Account *acc in accounts) {
        BankAccount *account = [BankAccount accountWithNumber:acc.accountNumber subNumber:acc.subNumber bankCode:acc.bankCode ];
        if (account == nil) {
            continue;
        }
        NSArray *supportedJobNames = acc.supportedJobs;
        
        if ([supportedJobNames containsObject:@"Ueb" ] == YES) {
            SupportedTransactionInfo *tinfo = [NSEntityDescription insertNewObjectForEntityForName:@"SupportedTransactionInfo" inManagedObjectContext:context];
            tinfo.account = account;
            tinfo.user = user;
            tinfo.type = [NSNumber numberWithInt:TransactionType_TransferStandard ];
            
            // Parameters
            if ([supportedJobNames containsObject:@"TermUeb" ] == YES) {
                tinfo.allowsDated = [NSNumber numberWithBool:YES];
            } else {
                tinfo.allowsDated = [NSNumber numberWithBool:NO];
            }
            if ([supportedJobNames containsObject:@"MultiUeb" ] == YES) {
                tinfo.allowsCollective = [NSNumber numberWithBool:YES];
            } else {
                tinfo.allowsCollective = [NSNumber numberWithBool:NO];
            }
        }
        
        // todo as soon as we support management of standing orders
        if ([supportedJobNames containsObject:@"TermUeb" ] == YES) {
            SupportedTransactionInfo *tinfo = [NSEntityDescription insertNewObjectForEntityForName:@"SupportedTransactionInfo" inManagedObjectContext:context];
            tinfo.account = account;
            tinfo.user = user;
            tinfo.type = [NSNumber numberWithInt:TransactionType_TransferDated ];
        }
        
        if ([supportedJobNames containsObject:@"UebForeign" ] == YES) {
            SupportedTransactionInfo *tinfo = [NSEntityDescription insertNewObjectForEntityForName:@"SupportedTransactionInfo" inManagedObjectContext:context];
            tinfo.account = account;
            tinfo.user = user;
            tinfo.type = [NSNumber numberWithInt:TransactionType_TransferEU ];
        }
        
        if ([supportedJobNames containsObject:@"UebSEPA" ] == YES) {
            SupportedTransactionInfo *tinfo = [NSEntityDescription insertNewObjectForEntityForName:@"SupportedTransactionInfo" inManagedObjectContext:context];
            tinfo.account = account;
            tinfo.user = user;
            tinfo.type = [NSNumber numberWithInt:TransactionType_TransferSEPA ];
        }
        
        if ([supportedJobNames containsObject:@"Umb" ] == YES) {
            SupportedTransactionInfo *tinfo = [NSEntityDescription insertNewObjectForEntityForName:@"SupportedTransactionInfo" inManagedObjectContext:context];
            tinfo.account = account;
            tinfo.user = user;
            tinfo.type = [NSNumber numberWithInt:TransactionType_TransferInternal ];
        }
        
        if ([supportedJobNames containsObject:@"Last" ] == YES) {
            SupportedTransactionInfo *tinfo = [NSEntityDescription insertNewObjectForEntityForName:@"SupportedTransactionInfo" inManagedObjectContext:context];
            tinfo.account = account;
            tinfo.user = user;
            tinfo.type = [NSNumber numberWithInt:TransactionType_TransferDebit ];
        }
        
        if ([supportedJobNames containsObject:@"DauerNew" ] == YES) {
            SupportedTransactionInfo *tinfo = [NSEntityDescription insertNewObjectForEntityForName:@"SupportedTransactionInfo" inManagedObjectContext:context];
            tinfo.account = account;
            tinfo.user = user;
            tinfo.type = [NSNumber numberWithInt:TransactionType_StandingOrder ];
            
            // Parameters
            if ([supportedJobNames containsObject:@"DauerEdit" ] == YES) {
                tinfo.allowsChange = [NSNumber numberWithBool:YES];
            } else {
                tinfo.allowsChange = [NSNumber numberWithBool:NO];
            }
            if ([supportedJobNames containsObject:@"DauerDel" ] == YES) {
                tinfo.allowesDelete = [NSNumber numberWithBool:YES];
            } else {
                tinfo.allowesDelete = [NSNumber numberWithBool:NO];
            }
        }
    }
    return nil;
}


-(PecuniaError*)updateBankDataForUser:(BankUser*)user
{
    PecuniaError *error=nil;
    if([self registerBankUser:user error:&error] == NO) return error;

    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"updateBankData\">" ];
    [self appendTag: @"bankCode" withValue: user.bankCode to: cmd ];
    [self appendTag: @"customerId" withValue: user.customerId to: cmd ];
    [self appendTag: @"userId" withValue: user.userId to: cmd ];
    [cmd appendString: @"</command>" ];
    
    // communicate with bank to update bank parameters
    User *usr = [bridge syncCommand: cmd error: &error ];
    if(error) return error;
    
    // Update user's accounts
    [self updateBankAccounts:usr.accounts forUser:user];
    
    // update supported transactions
    error = [self updateSupportedTransactionsForAccounts:usr.accounts user:user];
    if(error) return error;
        
    // also update TAN media and TAN methods
    if ([user.secMethod intValue ] == SecMethod_PinTan) {
        error = [self updateTanMethodsForUser:user ];
        if(error != nil) return error;
        error = [self updateTanMediaForUser:user ];
        if(error != nil) return error;
    }
    return nil;
}

-(PecuniaError*)changePinTanMethodForUser:(BankUser*)user
{
    PecuniaError *error=nil;
    if([self registerBankUser:user error:&error] == NO) return error;

    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"resetPinTanMethod\">" ];
    [self appendTag: @"bankCode" withValue: user.bankCode to: cmd ];
    [self appendTag: @"userId" withValue: user.userId to: cmd ];
    [cmd appendString: @"</command>" ];
    
    [bridge syncCommand: cmd error: &error ];
    if(error) return error;
    return nil;
}

-(PecuniaError*)sendCustomerMessage:(CustomerMessage*)msg
{
    PecuniaError *error=nil;
    
    [self startProgress ];
    
    BankUser *user = [BankUser userWithId:msg.account.userId bankCode:msg.account.bankCode ];
    if([self registerBankUser:user error:&error] == NO) return error;

    if ([user.tanMediaFetched boolValue] == NO) [self updateTanMediaForUser:user ];

    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"customerMessage\">" ];
    [self appendTag: @"bankCode" withValue: msg.account.bankCode to: cmd ];
    [self appendTag: @"accountNumber" withValue: msg.account.accountNumber to:cmd ];
    [self appendTag: @"subNumber" withValue: msg.account.accountSuffix to:cmd ];
    [self appendTag: @"userId" withValue: msg.account.userId to: cmd ];
    [self appendTag: @"head" withValue: msg.header to: cmd ];
    [self appendTag: @"body" withValue: msg.message to: cmd ];
    [self appendTag: @"recpt" withValue: msg.receipient to: cmd ];
    [cmd appendString: @"</command>" ];

    NSNumber *result = [bridge syncCommand: cmd error: &error ];
    [self stopProgress ];
    
    if(error) return error;

    if ([result boolValue ] == YES) {
        msg.isSent = [NSNumber numberWithBool:YES ];
    } else {
        error = [PecuniaError errorWithCode:0 message: NSLocalizedString(@"AP172", @"") ];
    }
    return error;
}

-(PecuniaError*)getBalanceForAccount:(BankAccount*)account
{
    PecuniaError *error=nil;
    
    [self startProgress ];
    
    BankUser *user = [account defaultBankUser ];
    if (user == nil) return nil;
    
    // BankUser registrieren
    if([self registerBankUser:user error:&error] == NO) return error;
    
    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"getBalance\">" ];
    [self appendTag: @"bankCode" withValue: account.bankCode to: cmd ];
    [self appendTag: @"accountNumber" withValue: account.accountNumber to:cmd ];
    [self appendTag: @"subNumber" withValue: account.accountSuffix to:cmd ];
    [self appendTag: @"userId" withValue: account.userId to: cmd ];
    [cmd appendString: @"</command>" ];
	
    NSDictionary *result = [bridge syncCommand: cmd error: &error ];
    [self stopProgress ];
    
    if(error) return error;
	if (result == nil) {
		[[MessageLog log ] addMessage: @"Unexpected result for getBalance: nil" withLevel: LogLevel_Error  ];
		return nil;
	}
	NSNumber *isOk = [result valueForKey:@"isOk" ];
	if (isOk != nil) {
		NSDecimalNumber *value = [result valueForKey:@"balance" ];
		if (value !=nil) {
			[account updateBalanceWithValue: value ];
		} else {
			[[MessageLog log ] addMessage: @"getBalance: no balance delivered" withLevel: LogLevel_Error  ];
			return nil;
		}
	} else {
		error = [PecuniaError errorWithCode:0 message: NSLocalizedString(@"AP402", @"") ];
	}
	return error;
}

-(PecuniaError*)updateTanMethodsForUser:(BankUser*)user
{
    PecuniaError *error=nil;
    if([self registerBankUser:user error:&error] == NO) return error;

    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"getTANMethods\">" ];
    [self appendTag: @"bankCode" withValue: user.bankCode to: cmd ];
    [self appendTag: @"userId" withValue: user.userId to: cmd ];
    [cmd appendString: @"</command>" ];
    
    NSArray *methods = [bridge syncCommand: cmd error: &error ];
    if (error) return error;
    [user updateTanMethods:methods ];
    return nil;
}

- (NSArray*)getSupportedBusinessTransactions: (BankAccount*)account
{
    PecuniaError *error = nil;
    
    BankUser *user = [account defaultBankUser ];
    if (user == nil) return nil;
    
    // BankUser registrieren
    if([self registerBankUser:user error:&error] == NO) {
        if (error) {
            [error alertPanel ];   
        }
        return nil;
    } 
    
    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"getSupportedBusinessTransactions\">" ];
    [self appendTag: @"bankCode" withValue: account.bankCode to: cmd];
    [self appendTag: @"accountNumber" withValue: account.accountNumber to: cmd];
    [self appendTag: @"subNumber" withValue: account.accountSuffix to: cmd];
    [self appendTag: @"userId" withValue: account.userId to: cmd];
    [cmd appendString: @"</command>" ];

    NSArray* result = [bridge syncCommand: cmd error: &error];
    if (error) {
        [error alertPanel ];
        return nil;
    }

    return result;
}

- (PecuniaError*)updateTanMediaForUser:(BankUser*)user
{
    PecuniaError *error=nil;
    if([self registerBankUser:user error:&error] == NO) return error;

    StatusBarController *sbController = [StatusBarController controller ];
    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"getTANMediaList\">" ];
    [self appendTag: @"bankCode" withValue: user.bankCode to: cmd ];
    [self appendTag: @"userId" withValue: user.userId to: cmd ];
    [cmd appendString: @"</command>" ];
    
    [sbController setMessage:NSLocalizedString(@"AP175", @"") removeAfter:0];
    [sbController startSpinning ];
    TanMediaList *mediaList = [bridge syncCommand: cmd error: &error ];
    [sbController stopSpinning ];
    [sbController clearMessage ];
    if (error) return error;
    [user updateTanMedia:mediaList.mediaList ];
    user.tanMediaFetched = [NSNumber numberWithBool:YES ];
    return nil;
}

- (BOOL)registerBankUser:(BankUser*)user error:(PecuniaError**)error
{
    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"registerUser\">" ];
    
    SecurityMethod secMethod = [user.secMethod intValue ];
    if (secMethod == SecMethod_DDV) {
        [self appendTag: @"passportType" withValue: @"DDV" to: cmd];
        user.tanMediaFetched = [NSNumber numberWithBool:YES ];
        [self appendTag: @"ddvPortIdx" withValue: [user.ddvPortIdx stringValue ] to: cmd];
        [self appendTag: @"ddvReaderIdx" withValue: [user.ddvReaderIdx stringValue ] to: cmd];
        [self appendTag: @"host" withValue: user.bankURL to: cmd ];
    } else {
        [self appendTag: @"passportType" withValue: @"PinTan" to: cmd];
        [self appendTag: @"host" withValue: [user.bankURL stringByReplacingOccurrencesOfString: @"https://" withString:@"" ] to: cmd ];
        [self appendTag: @"port" withValue: @"443" to: cmd ];
        if([user.noBase64 boolValue] == NO) [self appendTag: @"filter" withValue: @"Base64" to: cmd ];
    }
    [self appendTag: @"version" withValue: user.hbciVersion to: cmd];
    [self appendTag: @"userId" withValue: user.userId to: cmd];
    [self appendTag: @"customerId" withValue: user.customerId to: cmd ];
    [self appendTag: @"bankCode" withValue: user.bankCode to: cmd];
    [cmd appendString: @"</command>" ];
    
    NSNumber *isOk = [bridge syncCommand: cmd error: error];
    
    if (*error == nil && [isOk boolValue ] == YES) {
        return YES;
    } else {
        if (*error == nil) {
            *error = [PecuniaError errorWithMessage:[NSString stringWithFormat:NSLocalizedString(@"AP356",@""), user.userId ] title:NSLocalizedString(@"AP355",@"") ];
        }
        return NO;
    }   
}

-(NSArray*)getOldBankUsers
{
    PecuniaError *error=nil;
    NSMutableString *cmd = [NSMutableString stringWithFormat: @"<command name=\"getOldBankUsers\"></command>" ];
    NSArray *users = [bridge syncCommand: cmd error: &error ];
    if (error) {
        [error alertPanel ];
        return nil;
    }
    return users;
}

-(SigningOption*)signingOptionForAccount:(BankAccount*)account
{
    NSMutableArray *options = [NSMutableArray arrayWithCapacity:10 ];
    NSSet *users = account.users;
    if (users == nil || [users count] == 0) {
        [[MessageLog log ] addMessage: @"signingOptionForAccount: no users assigned to account" withLevel: LogLevel_Error];
        return nil;
    }
    for(BankUser *user in users) {
        SigningOption *option =  [user preferredSigningOption ];
        if (option) {
            [options addObject:option ];
        } else {
            [options addObjectsFromArray:[user getSigningOptions ] ];
        }
    }
    if ([options count ] == 0) {
        NSRunAlertPanel(NSLocalizedString(@"AP352", @""),
                        NSLocalizedString(@"AP353",@""),
                        NSLocalizedString(@"ok",@""), 
                        nil, nil, account.accountNumber);
        return nil;
    }
    if ([options count ] == 1) return [options lastObject ];

    SigningOptionsController *controller = [[SigningOptionsController alloc ] initWithSigningOptions:options forAccount: account ];
    int res = [NSApp runModalForWindow:[controller window ] ];
    if (res > 0) return nil;
    return [controller selectedOption ];
}

@end