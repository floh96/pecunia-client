/**
 * Copyright (c) 2009, 2012, Pecunia Project. All rights reserved.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; version 2 of the
 * License.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301  USA
 */

#import <Cocoa/Cocoa.h>

typedef enum {
	slice_none = -1,
	slice_year = 0,
	slice_quarter,
	slice_month,
} SliceType;

@class ShortDate;

@interface TimeSliceManager : NSObject {
    NSUInteger year;
    NSInteger quarter;
    NSUInteger month;
    SliceType type;
    
    ShortDate   *_minDate;
    ShortDate   *_maxDate;
    ShortDate   *_fromDate;
    ShortDate   *_toDate;
    NSString    *_autosaveName;
    
    IBOutlet NSDatePicker *fromPicker;
    IBOutlet NSDatePicker *toPicker;
    
    IBOutlet id delegate;
    IBOutlet NSSegmentedControl *control;
    IBOutlet NSSegmentedControl *upDown;
    
    NSMutableArray *controls;
}

@property (nonatomic, retain) ShortDate *_minDate;
@property (nonatomic, retain) ShortDate *_maxDate;
@property (nonatomic, retain) ShortDate *_fromDate;
@property (nonatomic, retain) ShortDate *_toDate;
@property (nonatomic, retain) NSString  *_autosaveName;

-(id)initWithYear: (int)y month: (int)m;
-(ShortDate*)lowerBounds;
-(ShortDate*)upperBounds;
-(void)stepUp;
-(void)stepDown;
-(void)stepIn: (ShortDate*)date;
-(void)setMinDate: (ShortDate*)date;
-(void)setMaxDate: (ShortDate*)date;

-(void)updateControl;
-(void)updateDelegate;
-(void)updatePickers;

-(IBAction)dateChanged: (id)sender;
-(IBAction)timeSliceChanged: (id)sender;
-(IBAction)timeSliceUpDown: (id)sender;

-(void)save;
-(NSPredicate*)predicateForField: (NSString*)field;
-(NSString*)description;

- (void)showControls: (BOOL)show;

//+(void)initialize;
+(TimeSliceManager*)defaultManager;


@end


extern TimeSliceManager *timeSliceManager;
