//
//  CatDefWindowController.m
//  Pecunia
//
//  Created by Frank Emminghaus on 03.09.08.
//  Copyright 2008 Frank Emminghaus. All rights reserved.
//

#import "CatDefWindowController.h"
#import "CatAssignClassification.h"
#import "BankStatement.h"
#import "MOAssistant.h"
#import "Category.h"
#import "CategoryView.h"
#import "MCEMOutlineViewLayout.h"
#import "MCEMTreeController.h"
#import "TimeSliceManager.h"
#import "ShortDate.h"

#define BankStatementDataType	@"BankStatementDataType"
#define CategoryDataType		@"CategoryDataType"

@implementation CatDefWindowController

-(id)init
{
	self = [super init ];
	if(self == nil) return nil;
	return self;
}

-(void)awakeFromNib
{
	NSError			*error;
	
	notAssignedSelected = NO;
	awaking = YES;
	
	// green color for cat view
/*	
	tc = [catView tableColumnWithIdentifier: @"balance" ];
	if(tc) {
		NSCell	*cell = [tc dataCell ];
		NSNumberFormatter	*form = [cell formatter ];
		if(form) {
			NSDictionary *newAttrs = [NSDictionary dictionaryWithObjectsAndKeys: 
									  [NSColor colorWithDeviceRed: 0.09 green: 0.7 blue: 0 alpha: 100], @"NSColor", nil ];
			[form setTextAttributesForPositiveValues: newAttrs ];
		}
	}
 */
 
	// default: hide values that are already assigned elsewhere
	hideAssignedValues = YES;
	[self setValue:[NSNumber numberWithBool:YES ]  forKey: @"hideAssignedValues" ];
	
	caClassification = [[CatAssignClassification alloc] init];
	[predicateEditor addRow:self ];
	if([catDefController fetchWithRequest:nil merge:NO error:&error]); // [catView restoreAll ];
	
	// sort descriptor for transactions view
	NSSortDescriptor	*sd = [[[NSSortDescriptor alloc] initWithKey:@"valutaDate" ascending:NO] autorelease];
	NSArray				*sds = [NSArray arrayWithObject:sd];
	[assignPreviewController setSortDescriptors: sds ];
	
	// register Drag'n Drop
	[assignPreview registerForDraggedTypes: [NSArray arrayWithObject: BankStatementDataType ] ];
	[catView registerForDraggedTypes: [NSArray arrayWithObjects: BankStatementDataType, CategoryDataType, nil ] ];
	
	[self performSelector: @selector(restoreCatView) withObject: nil afterDelay: 0.0];
	awaking = NO;
}

-(void)prepare
{
	[BankStatement setClassificationContext: caClassification ];
	[self calculateCatAssignPredicate ];
	
	// update values according to slicer
	Category *cat = [Category catRoot ];
	[Category setCatReportFrom: [timeSlicer lowerBounds ] to: [timeSlicer upperBounds ] ];
	[cat rebuildValues ];
	[cat rollup ];
}

-(void)restoreCatView
{
	[catView restoreAll ];
}

-(Category*)currentSelection
{
	NSArray* sel = [catDefController selectedObjects ];
	if(sel == nil || [sel count ] != 1) return nil;
	return [sel objectAtIndex: 0 ];
}
	
- (IBAction)add:(id)sender 
{
 	int i;
	NSError* error;
	Category *cat = [self currentSelection ];
	if(cat == nil) return;
	
	NSArray* trs = [assignPreviewController selectedObjects ];
	for(i=0; i<[trs count ]; i++) {
		BankStatement* stat = [trs objectAtIndex: i ];
		[stat assignToCategory: cat ];
	}
	[assignPreview setNeedsDisplay: YES ];
	
	[cat invalidateBalance ];
	[Category updateCatValues ];
	
	// save updates
	NSManagedObjectContext *context = [[MOAssistant assistant ] context ];
	if([context save: &error ] == NO) {
		NSAlert *alert = [NSAlert alertWithError:error];
		[alert runModal];
		return;
	}
}

- (IBAction)remove:(id)sender 
{
 	int i;
	NSError* error;
	Category *cat = [self currentSelection ];
	if(cat == nil) return;
	
	NSArray* trs = [assignPreviewController selectedObjects ];
	for(i=0; i<[trs count ]; i++) {
		BankStatement* stat = [trs objectAtIndex: i ];
		[stat removeFromCategory: cat ];
	}
	[assignPreview setNeedsDisplay: YES ];

	[cat invalidateBalance ];
	[Category updateCatValues ];

	// save updates
	NSManagedObjectContext *context = [[MOAssistant assistant ] context ];
	if([context save: &error ] == NO) {
		NSAlert *alert = [NSAlert alertWithError:error];
		[alert runModal];
		return;
	}
    
}

- (IBAction)saveRule:(id)sender 
{
	NSError* error;

	Category *cat = [self currentSelection ];
	if(cat == nil) return;
	
	NSPredicate* predicate = [predicateEditor objectValue];
	if(predicate) {
		[cat setValue: [predicate description ] forKey: @"rule" ];
	
		// save updates
		NSManagedObjectContext *context = [[MOAssistant assistant ] context ];
		if([context save: &error ] == NO) {
			NSAlert *alert = [NSAlert alertWithError:error];
			[alert runModal];
			return;
		}
	}
}

- (IBAction)deleteRule:(id)sender
{
	NSError* error;
	
	Category *cat = [self currentSelection ];
	if(cat == nil) return;

	int res = NSRunAlertPanel(NSLocalizedString(@"AP77", @""),
							  NSLocalizedString(@"AP78", @""),
							  NSLocalizedString(@"yes", @"Yes"),
							  NSLocalizedString(@"no", @"No"),
							  nil,
							  [cat localName ]
							  );
	if(res != NSAlertDefaultReturn) return;
	
	[cat setValue: nil forKey: @"rule" ];
	
	// save updates
	NSManagedObjectContext *context = [[MOAssistant assistant ] context ];
	if([context save: &error ] == NO) {
		NSAlert *alert = [NSAlert alertWithError:error];
		[alert runModal];
		return;
	}
	NSPredicate* pred = [NSCompoundPredicate predicateWithFormat: @"purpose CONTAINS[c] ''" ];
	if([pred class ] != [NSCompoundPredicate class ]) {
		NSCompoundPredicate* comp = [[NSCompoundPredicate alloc ] initWithType: NSOrPredicateType subpredicates: [NSArray arrayWithObjects: pred, nil ]];
		pred = comp;
	}
	[predicateEditor setObjectValue: pred ];
	
	[self calculateCatAssignPredicate ];
}

-(IBAction)addCategory: (id)sender
{
	Category *cat = [self currentSelection ];
	if(cat == nil) return;
	if([cat isRoot ]) return [self insertCategory: sender ];
	[catDefController add: sender ]; 
	[catView performSelector: @selector(editSelectedCell) withObject: nil afterDelay: 0.0];
}

-(IBAction)insertCategory: (id)sender
{
	[catDefController addChild: sender ];
	[catView performSelector: @selector(editSelectedCell) withObject: nil afterDelay: 0.0];
}


-(IBAction)manageCategories:(id)sender
{
	int clickedSegment = [sender selectedSegment];
    int clickedSegmentTag = [[sender cell] tagForSegment:clickedSegment];
	switch(clickedSegmentTag) {
		case 0: [self addCategory: sender ]; break;
		case 1: [self insertCategory: sender ]; break;
		case 2: [self deleteCategory: sender ]; break;
		default: return;
	}
}

-(NSString*)autosaveNameForTimeSlicer: (TimeSliceManager*)tsm
{
	return @"CatDefTimeSlice";
}

-(void)timeSliceManager: (TimeSliceManager*)tsm changedIntervalFrom: (ShortDate*)from to: (ShortDate*)to
{
	int idx = [mainTabView indexOfTabViewItem: [mainTabView selectedTabViewItem ] ];
	if(idx != 2) return;
	Category *cat = [Category catRoot ];
	[Category setCatReportFrom: from to: to ];
	[cat rebuildValues ];
	[cat rollup ];
	[self calculateCatAssignPredicate ];
}

-(void)controlTextDidBeginEditing:(NSNotification *)aNotification
{
	if([aNotification object ] == catView) {
		Category *cat = [self currentSelection ];
		catView.saveCatName = [[cat name ] retain];
	}	
}

-(void)controlTextDidEndEditing:(NSNotification *)aNotification
{
	if([aNotification object ] == catView) {
		Category *cat = [self currentSelection ];
		if([cat name ] == nil) {
			[cat setValue: [catView.saveCatName autorelease ] forKey: @"name" ];
		}
		[catDefController resort ];
		if(cat) [catDefController setSelectedObject: cat ];
	}
}

- (IBAction)deleteCategory: (id)sender
{
	Category *cat = [self currentSelection ];
	if(cat == nil) return;
	
	if([cat isRemoveable ] == NO) return;
	NSArray *stats = [[cat mutableSetValueForKey: @"statements" ] allObjects ];
	BankStatement *statement;
	
	if([stats count ] > 0) {
		int res = NSRunCriticalAlertPanel(NSLocalizedString(@"AP84", @"Delete category"),
										  NSLocalizedString(@"AP85", @"Category '%@' still has %d assigned transactions. Do you want to proceed anyway?"),
										  NSLocalizedString(@"no", @"No"),
										  NSLocalizedString(@"yes", @"Yes"),
										  nil,
										  [cat localName ],
										  [stats count ],
										  nil
										  );
		if(res != NSAlertAlternateReturn) return;
	}
	
	//  Delete bank statements from category first
	for(statement in stats) {
		[statement removeFromCategory: cat ];	
	}
	[catDefController remove: cat ];
	[Category updateCatValues ]; 
}


-(void)calculateCatAssignPredicate
{
	NSPredicate* pred = nil;
	NSPredicate* compound = nil;
	
	// first add selected category
	Category* cat = [self currentSelection ];
	if(cat == nil) return;
	if([cat valueForKey: @"parent" ] != nil) {
		pred = [NSPredicate predicateWithFormat: @"(%@ IN categories)", cat ];
	}
	
	// update classification Context
	if(cat == [Category nassRoot ]) [caClassification setCategory: nil]; else [caClassification setCategory: cat];
	
	// then add predicate definition
	NSPredicate* predicate = [predicateEditor objectValue];
	
	if(hideAssignedValues) {
		NSPredicate *pred2 = [NSPredicate predicateWithFormat: @"isAssigned = 0" ];
		compound = [NSCompoundPredicate andPredicateWithSubpredicates: [NSArray arrayWithObjects: pred2, predicate, nil ] ];
	} else compound = predicate;
	
	if(pred != nil)	compound = [NSCompoundPredicate orPredicateWithSubpredicates: [NSArray arrayWithObjects: pred, compound, nil ] ];

	// filter with from and to date?
	NSPredicate *pred3 = [NSPredicate predicateWithFormat: @"(valutaDate => %@) AND (valutaDate <= %@)", [[timeSlicer lowerBounds ] lowDate ], [[timeSlicer upperBounds ] highDate ] ];
    compound = [NSCompoundPredicate andPredicateWithSubpredicates: [NSArray arrayWithObjects: pred3, compound, nil ] ];
	
	// set new fetch predicate
	if(compound) [assignPreviewController setFilterPredicate: compound ];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	Category *cat = [item representedObject ];
	if(cat == nil) return NO;
//	return cat != [Category nassRoot ];
	return YES;
}
/*
- (BOOL)selectionShouldChangeInOutlineView:(NSOutlineView *)outlineView
{
	Category* cat = [self currentSelection ];
	if(cat == nil) return YES;
	int res = NSRunAlertPanel(NSLocalizedString(@"AP75", @""),
							  NSLocalizedString(@"AP76", @""),
							  NSLocalizedString(@"yes", @"Yes"),
							  NSLocalizedString(@"no", @"No"),
							  nil,
							  [cat localName ]
							  );
	if(res == NSAlertDefaultReturn) [self saveRule:self ];
	return YES;
}
*/

-(void)outlineViewSelectionDidChange:(NSNotification *)aNotification
{
	// first add selected category
	Category* cat = [self currentSelection ];
	if(cat == nil) return;
	
	if(cat == [Category nassRoot ]) {
		int i;
		NSArray *subviews = [rightSplitContent subviews ];
		NSRect frame = [rightSplitContent frame ];
		frame.origin.x = 0;
		for(i=0; i<[subviews count ]; i++) {
			NSView *cView = [subviews objectAtIndex:i ];
			if([cView tag ] == 1) [cView setHidden: YES ];
		}
		[[[predicateEditor superview] superview ] setHidden: YES ];
		
		[[[assignPreview superview ] superview ] setFrame: frame ];
		notAssignedSelected = YES;
	} else {
		if(notAssignedSelected) {
			int i;
			NSArray *subviews = [rightSplitContent subviews ];
			NSRect frame = [rightSplitContent frame ];
			frame.origin.x = 0; frame.origin.y = 20;
			frame.size.height -= 306;
			for(i=0; i<[subviews count ]; i++) {
				NSView *cView = [subviews objectAtIndex:i ];
				if([cView tag ] == 1) [cView setHidden: NO ];
			}
			[[[predicateEditor superview] superview ] setHidden: NO ];
			
			[[[assignPreview superview ] superview ] setFrame: frame ];
			notAssignedSelected = NO;
		}
	}
	
	// set states of categorie Actions Control
	[catActions setEnabled: [cat isRemoveable ] forSegment: 2 ];
	[catActions setEnabled: [cat isInsertable ] forSegment: 1 ];

	NSString* s = [cat valueForKey: @"rule" ];
	if(s == nil) s = @"purpose CONTAINS[c] ''";
	NSPredicate* pred = [NSCompoundPredicate predicateWithFormat: s ];
	if([pred class ] != [NSCompoundPredicate class ]) {
		NSCompoundPredicate* comp = [[NSCompoundPredicate alloc ] initWithType: NSOrPredicateType subpredicates: [NSArray arrayWithObjects: pred, nil ]];
		pred = comp;
	}
	[predicateEditor setObjectValue: pred ];
	[self calculateCatAssignPredicate ];
}

- (IBAction)predicateEditorChanged:(id)sender
{	
	if(awaking) return;
	// check NSApp currentEvent for the return key
    NSEvent* event = [NSApp currentEvent];
    if ([event type] == NSKeyDown)
	{
		NSString* characters = [event characters];
		if ([characters length] > 0 && [characters characterAtIndex:0] == 0x0D)
		{
			[self calculateCatAssignPredicate ];
		}
    }
    // if the user deleted the first row, then add it again - no sense leaving the user with no rows
    if ([predicateEditor numberOfRows] == 0)
		[predicateEditor addRow:self];
}

- (void)ruleEditorRowsDidChange:(NSNotification *)notification
{
	[self calculateCatAssignPredicate ];
}

- (IBAction)hideAssignedChanged:(id)sender
{
	[self calculateCatAssignPredicate ];
}


- (id)outlineView:(NSOutlineView *)outlineView persistentObjectForItem:(id)item 
{
    return [outlineView persistentObjectForItem: item ];
}

-(void)terminateController
{
	[catView saveLayout ];
}

// Dragging Bank Statements
- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet*)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
	unsigned int	idx[10], count, i;
	BankStatement	*bs;
	NSRange			range;
	NSMutableArray	*uris = [NSMutableArray arrayWithCapacity: 10 ];
	
	range.location = 0;
	range.length = 100000;
	
    // Copy the row numbers to the pasteboard.
	NSArray *objs = [assignPreviewController arrangedObjects ];
	
	do {
		count = [rowIndexes getIndexes: idx maxCount:10 inIndexRange: &range ];
		for(i=0; i < count; i++) {
			bs = [objs objectAtIndex: idx[i] ];
			NSURL *uri = [[bs objectID] URIRepresentation];
			[uris addObject: uri ];
		}
	} while(count > 0);
		
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: uris];
    [pboard declareTypes:[NSArray arrayWithObject: BankStatementDataType] owner:self];
    [pboard setData:data forType: BankStatementDataType];
	[tv setDraggingSourceOperationMask: NSDragOperationCopy | NSDragOperationMove forLocal: YES ];
    return YES;
}

// Drag Categories
- (BOOL)outlineView:(NSOutlineView*)ov writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard 
{
	Category		*cat;
	
	cat = [[items objectAtIndex:0 ] representedObject ];
	if(cat == nil) return NO;
	if([cat isBankAccount ]) return NO;
	if([cat isRoot ]) return NO;
	if(cat == [Category nassRoot ]) return NO;
	NSURL *uri = [[cat objectID] URIRepresentation];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: uri];
    [pboard declareTypes:[NSArray arrayWithObject: CategoryDataType] owner:self];
    [pboard setData:data forType: CategoryDataType];
	return YES;
}


- (NSDragOperation)outlineView:(NSOutlineView *)ov validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)childIndex
{
	NSPasteboard *pboard = [info draggingPasteboard];
	
    // This method validates whether or not the proposal is a valid one. Returns NO if the drop should not be allowed.
	if(childIndex >= 0) return NSDragOperationNone;
	if(item == nil) return NSDragOperationNone;
	Category* cat = (Category*)[item representedObject ];
	if([cat isBankAccount]) return NSDragOperationNone;
	
	NSString *type = [pboard availableTypeFromArray:[NSArray arrayWithObjects: BankStatementDataType, CategoryDataType, nil]];
	if(type == nil) return NO;
	if([type isEqual: BankStatementDataType ]) {
		Category *scat = [self currentSelection ];
		if([cat isRoot ]) return NSDragOperationNone;
		// not yet supported: move items to not assigned...
		if(cat == [Category nassRoot ]) return NSDragOperationNone;
		// if source is not assigned -> do move
		if(scat == [Category nassRoot ]) return NSDragOperationMove;
		NSDragOperation mask = [info draggingSourceOperationMask];
		if(mask == NSDragOperationCopy) return NSDragOperationCopy;
		return NSDragOperationMove;
	} else {
		NSManagedObjectContext	*context = [[MOAssistant assistant ] context ];
		NSData *data = [pboard dataForType: type ];
		NSURL *uri = [NSKeyedUnarchiver unarchiveObjectWithData: data ];
		NSManagedObjectID *moID = [[context persistentStoreCoordinator] managedObjectIDForURIRepresentation: uri ];
		Category *scat = (Category*)[context objectWithID: moID];
		if ([scat checkMoveToCategory:cat ] == NO) return NSDragOperationNone;
		return NSDragOperationMove;
	}
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)childIndex 
{
	int i;
	NSError *error;
	NSManagedObjectContext	*context = [[MOAssistant assistant ] context ];
	Category *cat = (Category*)[item representedObject ];
	NSPasteboard *pboard = [info draggingPasteboard];
	NSString *type = [pboard availableTypeFromArray:[NSArray arrayWithObjects: BankStatementDataType, CategoryDataType, nil]];
	if(type == nil) return NO;
	NSData *data = [pboard dataForType: type ];

	if([type isEqual: BankStatementDataType ]) {
		NSDragOperation mask = [info draggingSourceOperationMask];
		NSArray *uris = [NSKeyedUnarchiver unarchiveObjectWithData: data ];
		for(i=0; i<[uris count ]; i++) {
			NSURL *uri = [uris objectAtIndex: i ];
			NSManagedObjectID *moID = [[context persistentStoreCoordinator] managedObjectIDForURIRepresentation: uri ];
			if(moID == nil) continue;
			BankStatement *bs = (BankStatement*)[context objectWithID: moID];
			if(mask == NSDragOperationCopy) [bs assignToCategory: cat ]; else {
				[bs moveFromCategory: [self currentSelection ] toCategory: cat ];
				[assignPreviewController fetch: self ];
			}
		}
		[assignPreview reloadData ];
		[assignPreview setNeedsDisplay: YES ];

		[cat invalidateBalance ];
		[Category updateCatValues ];
	} else {
		NSURL *uri = [NSKeyedUnarchiver unarchiveObjectWithData: data ];
		NSManagedObjectID *moID = [[context persistentStoreCoordinator] managedObjectIDForURIRepresentation: uri ];
		if(moID == nil) return NO;
		Category *scat = (Category*)[context objectWithID: moID];
		[scat setValue: cat forKey: @"parent" ];
		[[Category catRoot ] rollup ];
	}
	
	// save updates
	if([context save: &error ] == NO) {
		NSAlert *alert = [NSAlert alertWithError:error];
		[alert runModal];
		return NO;
	}
	return YES;
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	Category *cat = [item representedObject ];
	if(cat == nil) return;
	if([[tableColumn identifier ] isEqualToString: @"category" ]) {
		if([cat isRoot ]) {
			NSColor *txtColor;
			if([cell isHighlighted ]) txtColor = [NSColor whiteColor]; 
			else txtColor = [NSColor colorWithCalibratedHue: 0.6194 saturation: 0.32 brightness:0.56 alpha:1.0 ];
			NSFont *txtFont = [NSFont fontWithName: @"Arial Rounded MT Bold" size: 13];
			NSDictionary *txtDict = [NSDictionary dictionaryWithObjectsAndKeys: txtFont,NSFontAttributeName,txtColor, NSForegroundColorAttributeName, nil];
			NSAttributedString *attrStr = [[[NSAttributedString alloc] initWithString: [cat localName ] attributes:txtDict] autorelease];
			[cell setAttributedStringValue:attrStr];
		}
	}
	if([[tableColumn identifier ] isEqualToString: @"balance" ]) {
		if([cell isHighlighted ]){
			[(NSTextFieldCell*)cell setTextColor: [NSColor whiteColor ] ];
		} else {
			if([[cat catSum ] doubleValue ] >= 0) [(NSTextFieldCell*)cell setTextColor: [NSColor colorWithDeviceRed: 0.09 green: 0.7 blue: 0 alpha: 100]];
			else [(NSTextFieldCell*)cell setTextColor: [NSColor redColor ] ];
		} 
	}
}


- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset
{
	if(offset==0) return 270;
	return proposedMin;
}


-(void)dealloc
{
	[caClassification release ];
	[super dealloc ];
}

@end
