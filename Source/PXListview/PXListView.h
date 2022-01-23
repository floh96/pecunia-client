//
//  PXListView.h
//  PXListView
//
//  Created by Alex Rozanski on 29/05/2010.
//  Copyright 2010 Alex Rozanski. http://perspx.com. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "PXListViewDelegate.h"
#import "PXListViewCell.h"


#if DEBUG
#define PXLog(...)	NSLog(__VA_ARGS__)
#endif


@interface PXListView : NSScrollView
{
	id <PXListViewDelegate> _delegate;
	
	NSMutableArray *_reusableCells;
	NSMutableArray *_visibleCells;
	NSRange _currentRange;
	
	NSUInteger _numberOfRows;
	NSMutableIndexSet *_selectedRows;
	
	NSRange _visibleRange;
	CGFloat _totalHeight;
	CGFloat *_cellYOffsets;
	
	CGFloat _cellSpacing;

	BOOL _allowsEmptySelection;
	BOOL _allowsMultipleSelection;
    NSInteger _selectionAnchor;
    
	BOOL _verticalMotionCanBeginDrag;
    
    BOOL _usesLiveResize;
    CGFloat _widthPriorToResize;
	
	NSUInteger _dropRow;
	PXListViewDropHighlight	_dropHighlight;
    
    BOOL _updating;
}

@property (nonatomic, weak) IBOutlet id <PXListViewDelegate> delegate;

@property (nonatomic, strong) NSIndexSet *selectedRows;
@property (nonatomic, assign) NSInteger selectedRow; // If nothing is selected -1 is returned

@property (nonatomic, assign) BOOL allowsEmptySelection;
@property (nonatomic, assign) BOOL allowsMultipleSelection;
@property (nonatomic, assign) BOOL verticalMotionCanBeginDrag;

@property (nonatomic, assign) CGFloat cellSpacing;
@property (nonatomic, assign) BOOL usesLiveResize;

- (void)reloadData;
- (void)rebuild;
- (void)reloadRowAtIndex:(NSInteger)inIndex;

- (PXListViewCell*)dequeueCellWithReusableIdentifier:(NSString*)identifier;

- (void)updateCells;
- (NSUInteger)numberOfRows;
- (NSArray*)visibleCells;
-(PXListViewCell *)cellForRowAtIndex:(NSUInteger)inIndex;

- (NSRange)visibleRange;
- (NSRect)rectOfRow:(NSUInteger)row;
- (NSRect)rectOfRow: (NSUInteger)row forDragging: (BOOL)forDragging;
- (void)deselectRows;
- (void)selectRowIndexes:(NSIndexSet*)rows byExtendingSelection:(BOOL)doExtend;

- (void)scrollRowToVisible:(NSUInteger)row;

@end
