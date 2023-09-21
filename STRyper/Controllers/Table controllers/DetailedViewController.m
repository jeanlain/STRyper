//
//  DetailedViewController.m
//  STRyper
//
//  Created by Jean Peccoud on 26/08/12.
//  Copyright (c) 2012 Jean Peccoud. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.



#import "DetailedViewController.h"
#import "Chromatogram.h"
#import "Trace.h"
#import "Genotype.h"
#import "Mmarker.h"
#import "MainWindowController.h"
#import "SampleTableController.h"
#import "MarkerView.h"
#import "TraceScrollView.h"
#import "STableRowView.h"

@interface DetailedViewController ()




/************ properties that we bind to the user defaults equivalent ******/


/// Whether the `topFluoMode` property  returns `topFluoModeHighestPeak`. We use it to bind to the equivalent property in traceViews, as traceViews themselves auto scale
@property (nonatomic) BOOL autoScaleToHighestPeak;

/// The default start size for the visibleRange of traceViews
@property (nonatomic) float defaultStartSize;

/// The default end size for the visibleRange of traceViews
@property (nonatomic) float defaultEndSize;
															
/// The default visibleRange of traceViews, derived from the defaultStartSize and defaultEnSize
@property (nonatomic) BaseRange defaultRange;


/// Whether the content the outline views shows corresponds to genotypes.
@property (nonatomic) BOOL showGenotypes;

/// Whether the outline views shows marker. We bind this property to the visibility of certain buttons.
@property (nonatomic) BOOL showMarkers;
															
/// A button that we may show to ask the user for confirmation to load a large number or samples or genotypes in the outline view
@property (nonatomic) NSButton *loadContentButton;

/// A textfield indicating the number of stacked samples that are shown, in place of the table header view
@property (nonatomic) NSTextField *stackedSampleTextfield;

/// The channels (as integers) that are currently displayed
@property (nonatomic) NSArray<NSNumber *> *displayedChannels;

/// the height of rows showing traces or markers, given the window size and the number of traces per window that the user wishes to see.
/// Its setter makes changes on the outline view
@property (nonatomic) float traceRowHeight;

@end



@implementation DetailedViewController
	
	/// Notes on the implementation:
	/// We use an outline view to show content, as it can convey the hierarchy between two entities:
	/// ``Chromatogram``/``Genotype`` objects , which are represented as regular rows, as in the sample table. They are the "parents".
	///
	/// The children are the chromatograms' traces (``Trace`` class), which show in custom row views.
	/// These row views don't have any table cell views.
	///
	/// This hierarchy facilitates the managing of the data source and showing/hiding channels.
	/// For each genotypes, there is only one channel per view at the range corresponding to the marker. Some setting buttons become hidden (stack channels and traces, and sync view), as they aren't relevant
	///
	/// When samples are selected, there are several display modes (see StackMode typdef)
	/// When genotypes are selected, a regular row showing samples information in several column is followed by a tall row showing the trace of the sample at the corresponding marker
	/// When markers are selected, one tall row per marker shows bins and the marker range (like in genotype mode when bin editing is enabled, but without the trace behind).
	///
	/// We don't use many of the TableViewController methods as the user cannot select nor remove items from the outline view, but we use those creating columns, the table header menu and some table cell views, mainly

{
	NSArray<NSButton *> *channelButtons;	/// array containing references to the round buttons allowing to show/hide channels.
											/// We use this array for quicker access as there are other buttons
															
	__weak NSOutlineView *traceOutlineView;  /// the outline view showing traces and/or markers, of which this object is the delegate and which is also the view we control
														
	BaseRange referenceRange;				/// used to synchronize the visible range of traceViews
	float referenceTopFluoLevel;			/// used to synchronize the vertical scale of traceViews

	NSMutableSet<TraceView *> *traceViews;	/// the set of visible trace views that we use to synchronize them
											/// I believe it is faster than enumerating all rows of the outline view at each scroll step

}



static NSArray<NSString *> *channelPreferenceKeys;				/// a convenience array we use to bind values of channel buttons to the corresponding user default key and to determine which button to disable

static const float defaultRowHeight = 20.0;
static const float minTraceRowHeight = 40.0;


+ (instancetype)sharedController {
	static DetailedViewController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = [[self alloc] init];
	});
	return controller;
}


- (instancetype)init {
	return [super initWithNibName:@"RightPane" bundle:nil];
}


-(NSDictionary *)columnDescription {
	return SampleTableController.sharedController.columnDescription;
}


- (NSTableView *)viewForCellPrototypes {
	return SampleTableController.sharedController.tableView;
}


- (NSArray<NSString *> *)orderedColumnIDs {
	return [SampleTableController.sharedController orderedColumnIDs];
}


- (nullable NSArrayController *)tableContent {
	return nil;
}


- (void)viewDidLoad {
	channelPreferenceKeys = @[ShowChannel0, ShowChannel1, ShowChannel2, ShowChannel3, ShowChannel4];
	NSMutableArray *channelButtonArray = NSMutableArray.new;
	

	/// we apply bindings to the display buttons
	/// we make an array of some preferences keys to bind to some buttons, based on the button tags (used to fetch the corresponding key in the array):
	NSArray *prefKeys = @[TraceTopFluoMode, SynchronizeViews, ShowOffScale, ShowBins, TraceStackMode];
	for (NSControl *control in self.view.subviews) {
		if([control isKindOfClass: NSButton.class] || [control isKindOfClass: NSSegmentedControl.class]) {
			/// all buttons must be hidden when the outline view shows markers, except the slider that controls row height
			[control bind:NSHiddenBinding toObject:self withKeyPath:NSStringFromSelector(@selector(showMarkers)) options:nil];
			if(control.tag >= 0 || control.tag == -5) {
				/// some buttons must be also hidden when it shows genotypes. We use their tag to determine which.
				[control bind:@"hidden2" toObject:self withKeyPath:NSStringFromSelector(@selector(showGenotypes)) options:nil];
				if(control.tag < 5 && control.tag >=0) {
					/// these are buttons controlling the channel to show. Their tags represent the channels from 0 to 4.
					[channelButtonArray addObject:control];
					[control bind:NSValueBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:channelPreferenceKeys[control.tag] options:nil];
				}
			}
			if(control.tag < 0) {
				if([control isKindOfClass: NSButton.class]) {
					[control bind:NSValueBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:prefKeys[-control.tag -1] options:nil];
					if(control.tag == -2) {
						/// The button that controls the horizontal synchronization is disabled when genotypes are shown.
						[control bind:NSEnabledBinding toObject:self
						  withKeyPath:NSStringFromSelector(@selector(showGenotypes))
							  options:@{NSValueTransformerNameBindingOption:NSNegateBooleanTransformerName}];
					}
				} else if([control isKindOfClass: NSSegmentedControl.class]) {
					[control bind:NSSelectedIndexBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:prefKeys[-control.tag -1] options:nil];
				}
			}
		} else if([control isKindOfClass:NSSlider.class]) {
			[control bind:NSValueBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:TraceRowsPerWindow options:nil];
		}
	}
	
	channelButtons = [NSArray arrayWithArray:channelButtonArray];
		
	traceOutlineView = (NSOutlineView *)self.tableView;
	
	[super viewDidLoad];
	
	[[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(windowDidResize:) name:NSWindowDidResizeNotification object:traceOutlineView.window];  /// to react to the window changing size and set the height of rows accordingly
	
	[self bind:@"defaultStartSize" toObject:NSUserDefaults.standardUserDefaults withKeyPath:DefaultStartSize options:nil];
	[self bind:@"defaultEndSize" toObject:NSUserDefaults.standardUserDefaults withKeyPath:DefaultEndSize options:nil];


	if(!self.displayedChannels) {
		[self setDisplayedChannels];
	}
	
	/// we set the default visible range of trace views
	referenceRange = MakeBaseRange(-1, -1);
	
	referenceTopFluoLevel = -1.0;
	
	traceViews = NSMutableSet.new;
	
}


- (NSButton *)loadContentButton {
	if(!_loadContentButton && traceOutlineView.superview) {
		/// we place the button asking for confirmation to load the content at the center of the visible rectangle of the outline view, i.e. in its clipview
		/// placing it in the enclosing scrollview works, but the centering of the button (below) has no effect
		NSView *view = traceOutlineView.superview;
		_loadContentButton = [traceOutlineView makeViewWithIdentifier:@"loadContentButton" owner:self];
		_loadContentButton.translatesAutoresizingMaskIntoConstraints = NO;
		[view addSubview:_loadContentButton];
		/// we center the button horizontally and vertically in its view
		[[_loadContentButton.centerXAnchor constraintEqualToAnchor:view.centerXAnchor] setActive:YES];
		[[_loadContentButton.bottomAnchor constraintEqualToAnchor:view.centerYAnchor] setActive:YES];
		_loadContentButton.target = self;
		_loadContentButton.action = @selector(loadContent:);
		
	}
	return _loadContentButton;
}


- (NSTextField *)stackedSampleTextfield {
	if(!_stackedSampleTextfield && traceOutlineView.headerView) {
		_stackedSampleTextfield = [NSTextField labelWithString:@"Several samples stacked"];
		NSTableHeaderView *headerView = traceOutlineView.headerView;
		_stackedSampleTextfield.translatesAutoresizingMaskIntoConstraints = NO;
		[headerView.superview addSubview:_stackedSampleTextfield];
		[[_stackedSampleTextfield.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor] setActive:YES];
		[[_stackedSampleTextfield.centerXAnchor constraintEqualToAnchor:headerView.centerXAnchor] setActive:YES];
	}
	return _stackedSampleTextfield;
}


- (BOOL)shouldMakeTableHeaderMenu {
	return YES;
}


- (BOOL)canSortByMultipleColumns {
	return NO;
}



#pragma mark - methods to populate the outline view showing traces (or markers)


- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
	if (item == nil) {
		NSInteger count = self.contentArray.count;		/// the number of parent rows is by default the number of items in the content array
		if(count == 0 || self.contentArray.firstObject == NSNull.null) {
			return 0;
		}
		return (self.stackMode == stackModeSamples && !self.showGenotypes && !self.showMarkers)? self.displayedChannels.count : count;  /// if we stack sample curves, the number of rows is the number of channels to show
	}
	if([item isKindOfClass: Genotype.class]) {
		return 1;	/// a genotype has one child, which is the trace corresponding to the marker's channel for the chromatogram
	}
	
	if([item isKindOfClass: Chromatogram.class]) {
		/// the number of children of a chromatogram depends on whether the channels are stacked or not
		return (self.stackMode == stackModeChannels && !self.showGenotypes)? 1 : self.displayedChannels.count;  /// which is the number of rows in each sample (1 if channels overlap, or the number of channels to show separately, depending on the view setting)
	}
	return 0;	/// other types of items have no children as they are represented by trace rows. They are not expandable.
}

- (id) outlineView:(id)outlineView child:(NSInteger)index ofItem:(id)item {
	if (item == nil) {  /// the top-level rows
		if (self.stackMode == stackModeSamples && !self.showGenotypes && !self.showMarkers) {
			/// here, samples are stacked
			/// if the child index, which should correspond to the channel to show, exceeds the displayedChannels array, we return a null object
			/// (but this would mean there is a bug somewhere)
			if(self.displayedChannels.count <= index) {
				return NSNull.null;
			}
			return [self tracesForChannel:self.displayedChannels[index].intValue]; 	/// if a row should show all traces of a given channel in an array, we return these traces
		}
		/// here, we don't stake samples, so we simply return the item at the corresponding index from the content array
		/// This could be a chromatogram, a marker, or a genotype
		if(self.contentArray.count < index+1) {
			return NSNull.null;
			/// this also prevents a crash. But if it we return a null object, it means there's a bug somewhere
		}
		/// else we return the sample/genotype at the given index (row number), whose metadata will populate standard rows with text fields
		return self.contentArray[index] ;
	}
	if([item isKindOfClass:Genotype.class]) {
		/// When the parent is a genotype, there is just one trace row below the parent row. The trace row will load the genotype, hence we need to return it
		/// but we must differentiate the child from the parent (to avoid an infinite loop).
		/// So we enclose the genotype in an NSSet (there may be be a more elegant solution for that). NSArray is already used for traces.
		return [NSSet setWithObject:item];
	}
	
	/// If we're here, it means that the parent is a sample.
	if(self.stackMode == stackModeChannels && !self.showGenotypes) {
		/// if we stack channels in the same view (the second condition is probably redundant),
		/// we return the sample, but enclosed in an NSSet to differentiate the child from the parent
		return [NSSet setWithObject:item];
	}
	/// if we're here, it means that we don't stack channels in the same view
	if(self.displayedChannels.count <= index) {
		return NSNull.null;
	}
	Trace *trace =[item traceForChannel: self.displayedChannels[index].intValue];	/// the child row will show the sample's trace for the correct channel
	if(!trace) {
		return NSNull.null;		/// if there is no trace for that channel, we return a null object.
	}
	return @[trace];  			/// else we return the trace in an array (a trace view is designed to show multiple traces, which we always return in an array)
}


- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
	return YES;		/// all items that have children are expanded (and can't be collapsed)
}


- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {

	if([item isKindOfClass: Genotype.class]) {
		return [item sample];
		/// for a regular row representing a genotype, we actually show the information from the sample.
		/// We don't show genotype information in the cells (status, marker, allele size, etc.). We could do that, but this would require replacing the columns
		/// Plus, all genotype information is visible in the trace view themselves (marker name, color, alleles...)
	}
	return item;  /// else, we return nil because the row corresponding to the item has no cell view (see viewForTableColumn:)
}


- (NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item {
	if(item == NSNull.null || ([item isKindOfClass:NSArray.class] && [item count] == 0)) {
		/// case where there is no trace for the required channel. We have a special row view in the nib,
		/// which has a textfield showing that there is no data for the channel
		return [outlineView makeViewWithIdentifier:@"noTraceRowViewKey" owner:self];
	}
	
	if([item isKindOfClass: Chromatogram.class] || [item isKindOfClass:Genotype.class]) {
		/// if the item is a chromatogram or a genotype, we return a standard row view that will include cells showing sample information
		/// (the identifier could be any identifier not corresponding to a view present in the xib)
		return [outlineView makeViewWithIdentifier:@"StandardRowView" owner:self];
	}
	
	///otherwise, the row should show a trace-view that will load traces, a genotype, or a marker
	NSTableRowView *rowView = [outlineView makeViewWithIdentifier:@"TraceRowViewKey" owner:self];   
	
	if(!rowView) {
		rowView = [STableRowView.alloc initWithFrame:NSMakeRect(0, 0, outlineView.bounds.size.width, self.traceRowHeight)];
		rowView.identifier = @"TraceRowViewKey";
		TraceScrollView *scrollView = [[TraceScrollView alloc] initWithFrame:rowView.bounds];
		scrollView.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
		[rowView addSubview:scrollView];
		
		TraceView* traceView = [[TraceView alloc] initWithFrame:rowView.bounds];
		traceView.delegate = self;
		scrollView.documentView = traceView;
		
		[traceView bind:ShowBinsBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:ShowBins options:nil];
		[traceView bind:ShowPeakTooltipsBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:ShowPeakTooltips options:nil];
		[traceView bind:ShowOffScaleRegionsBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:ShowOffScale options:nil];
		[traceView bind:ShowRawDataBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:ShowRawData options:nil];
		[traceView bind:MaintainPeakHeightsBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:MaintainPeakHeights options:nil];
		[traceView bind:AutoScaleToHighestPeakBinding toObject:self withKeyPath:@"autoScaleToHighestPeak" options:nil];
		[traceView bind:IgnoreCrossTalkPeaksBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:IgnoreCrosstalkPeaks options:nil];
		[traceView bind:DisplayedChannelsBinding toObject:self withKeyPath:@"displayedChannels" options:nil];
		[traceView bind:DefaultRangeBinding toObject:self withKeyPath:@"defaultRange" options:nil];
		[scrollView bind:AllowSwipeBetweenMarkersBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:SwipeBetweenMarkers options:nil];
		
		/// to manage the change in theme (dark/light), we bind the App's appearance to a private property in the view.
		/// We need to because the view uses CALayer, whose colors must be reset in response to the change.
		/// We don't use the viewDidChangeEffectiveAppearance method, because this method is not called on rows that are in the reuse queue and not visible.
		/// These view's CALayer objects would keep the previous appearance.
		/// We only bind to the traceView. It will notify other views at the same row (the marker view, for instance, see below) of the change in appearance. 
		[traceView bind:@"viewAppearance" toObject:NSApp withKeyPath: @"effectiveAppearance" options:nil];

		MarkerView *markerView = traceView.markerView;
		if(markerView) {
			/// we make some bindings to hide the marker view when the user has chosen that setting
			[markerView bind:NSHiddenBinding toObject: NSUserDefaults.standardUserDefaults withKeyPath:ShowMarkerView
					 options:@{NSValueTransformerNameBindingOption : NSNegateBooleanTransformerName}];
		}
	}
	
	return  rowView;
	
}


- (void)outlineView:(NSOutlineView *)outlineView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
	if ([rowView.identifier isEqualToString:@"TraceRowViewKey"]) {
		/// this is where we load the traceView with content. We don't do it in -outlineView:rowViewForItem since at that stage, the size of the row view may not be determined
		/// this would end up in wrong geometry for the traces
		id item = [traceOutlineView itemAtRow:row];
		TraceView* traceView = [rowView viewWithTag:1];
		if(!traceView) {
			return;
		}
		[traceViews addObject:traceView];
		if([item isKindOfClass:NSArray.class]) {		/// an array means that we should show traces
			[traceView loadTraces:item];
		} else if([item isKindOfClass:Mmarker.class]) {
			[traceView loadMarker:item];
		} else if([item isKindOfClass:NSSet.class]) {	/// an NSSet should include the genotype or sample to load
			id itemToLoad = [item anyObject];
			if([itemToLoad isKindOfClass:Genotype.class]) {
				[traceView loadGenotype:itemToLoad];
			} else if([itemToLoad isKindOfClass:Chromatogram.class]) {
				[traceView loadSample:itemToLoad];
			}
		}
	} else if ([rowView.identifier isEqualToString:@"noTraceRowViewKey"])  {
		rowView.backgroundColor = NSColor.orangeColor;		// setting this in rowViewForItem: has no effect for some reason
	}
}


- (void)outlineView:(NSOutlineView *)outlineView didRemoveRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
	if ([rowView.identifier isEqualToString:@"TraceRowViewKey"]) {
		TraceView* traceView = [rowView viewWithTag:1];
		if(traceView) {
			[traceView clearContents];
			[traceViews removeObject:traceView];
		}
	}
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
	if (![item isKindOfClass: Chromatogram.class] && ![item isKindOfClass: Genotype.class]) {
		return nil;  					/// if the item isn't a Chromatogram, the row has no cell (traces and markers are shown in the row view)
	}
	
	/// otherwise, we return table cells views whose prototype are in the sampleTable
	NSTableCellView *view = (NSTableCellView *)[super tableView:outlineView viewForTableColumn:tableColumn row:0];
	NSTextField *textField = view.textField;
	if(textField) {
		textField.controlSize = NSControlSizeRegular;
		textField.font = [NSFont systemFontOfSize:13.0];	/// the font is a little bigger than in the sample table
	}
	return view;
}



- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
	return NO;  /// the outline view is not meant to select any row:

}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item {
	return NO;   /// we don't allow collapsing anything.
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item {
	return NO;
}


- (NSArray<Trace *> *)tracesForChannel:(NSInteger) channel {
	/// we return all traces of a give channel. Called when samples are stacked
	NSMutableArray *traces = [NSMutableArray arrayWithCapacity:self.contentArray.count];
	for(Chromatogram *sample in self.contentArray) {
		if([sample respondsToSelector:@selector(traceForChannel:)]) {
			Trace *trace = [sample traceForChannel:channel];
			if(trace) {
				[traces addObject:trace];
			}
		}
	}
	return traces;
}

#pragma mark - setting contents

- (void)setContentArray:(NSArray *)content {
	if(content.count > 0) {
		self.showMarkers = [content.firstObject isKindOfClass: Mmarker.class];
		self.showGenotypes =  [content.firstObject isKindOfClass: Genotype.class];
	}
	int maxItems = 400;		/// 400 is close to a 384-sample plate
	NSString *itemType = @"Samples";
	if(self.showGenotypes) {
		maxItems = 1000;
		itemType = @"Genotypes";
	}
	
	/// we don't immediately load the content if the number of items to show is very large, which may take some time and block the UI
	/// The user may have selected the whole source table (of samples or genotypes) for another reason that viewing traces
	/// instead, we show a button asking for confirmation
	if(content.count < maxItems) {
		self.loadContentButton.hidden = YES;
	} else {
		self.loadContentButton.hidden = NO;
		self.loadContentButton.title = [NSString stringWithFormat:@"Show %ld %@", content.count, itemType];
		
		/// we show no content behind the button, but we need to differentiate this case from a case where no sample is selected.
		/// Otherwise, the binding machinery would see no change in content if all samples get deselected.
		/// Hence this setter won't be called and the button would still show.
		content = @[NSNull.null];
	}

	[self loadContentArray:content];
	
}


- (void)setShowGenotypes:(BOOL)showGenotypes {
	_showGenotypes = showGenotypes;
	if(showGenotypes) {
		/// if genotypes are shown, the detailed view columns cannot be used for sorting as they do not correspond to those of the genotype table
		/// to avoid confusing the user, we disable sorting.
		[traceOutlineView unbind:NSSortDescriptorsBinding];
		for (NSTableColumn *column in traceOutlineView.tableColumns) {
			/// We must remove the sort descriptor prototype of each column, otherwise the chevron still appears on the header
			column.sortDescriptorPrototype = nil;
		}
	} else {
		/// We re-enable sorting when the table no longer show genotypes
		/// (when it shows marker, the header is hidden anyway)
		NSDictionary *columnDescription = self.columnDescription;
		for (NSTableColumn *column in traceOutlineView.tableColumns) {
			column.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:columnDescription[column.identifier][KeyPathToBind] ascending:YES];
		}
		[traceOutlineView bind:NSSortDescriptorsBinding toObject:SampleTableController.sharedController.samples withKeyPath:NSStringFromSelector(@selector(sortDescriptors)) options:nil];

	}
}


-(void)loadContentArray:(NSArray *)content {
	if(!content ) {
		content = NSArray.new;
	}
	
	BOOL tooMany = content.firstObject == NSNull.null;
	
	if(content.count > 0 && !tooMany) {
		self.loadContentButton.hidden = YES;
	}

	/// when the selection of samples/genotypes/markers to show changes, we may react to that by removing and inserting rows instead of just reloading the view
	/// so we compare the new content to the current one
	NSArray *previousContent = self.contentArray;
	
	_contentArray = content;
	
	if(tooMany) {
		content = NSArray.new;
	}
	
	if(!self.showMarkers && !self.showGenotypes) {
		[self setDisplayedChannels];
	}
	
	/// if we show samples in separate rows, markers or genotypes (which are always one per row), we do some animation if the new contents contain items that were previously shown
	/// we don't do it if the number of items are too different between the new and previous content.
	int diffCount = abs((int)previousContent.count - (int)content.count);
	if ((self.stackMode != stackModeSamples || self.showGenotypes || self.showMarkers) && diffCount <= 10 && diffCount > 0) {
		NSIndexSet *rowsToInsert = [content indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return [previousContent indexOfObjectIdenticalTo:obj] == NSNotFound;  // gets the index of samples/genotypes that were not shown previously
		}];
		
		NSIndexSet *rowsToRemove = [previousContent indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return [content indexOfObjectIdenticalTo:obj] == NSNotFound;
		}];
		
		NSMutableArray *remaining = [NSMutableArray arrayWithArray:previousContent];
		if(rowsToRemove.count > 0) {
			[remaining removeObjectsAtIndexes:rowsToRemove];
		}
		
		NSMutableArray *remaining2 = [NSMutableArray arrayWithArray:content];
		if(rowsToInsert.count > 0) {
			[remaining2 removeObjectsAtIndexes:rowsToInsert];
		}
		
		/// if some element(s) is/are still showing and are in the same order, we make some animation. This helps the user understand what happens
		if (rowsToRemove.count < previousContent.count && [remaining isEqualToArray:remaining2]) {
			/// we don't animate if the number of rows to show hasn't changed (it would be more disturbing than anything)
			NSInteger animation = content.count == previousContent.count? NSTableViewAnimationEffectNone : NSTableViewAnimationEffectFade;
			
			[traceOutlineView beginUpdates];
			[traceOutlineView removeItemsAtIndexes:rowsToRemove inParent:nil withAnimation:animation];
			/// it's important to remove obsolete rows before inserting new one, and not doing the reverse
			[traceOutlineView insertItemsAtIndexes:rowsToInsert inParent:nil withAnimation:animation];
			[traceOutlineView endUpdates];
			[traceOutlineView expandItem:nil expandChildren:YES];
			[self updateHeader];
			return;
		}
	}
	[self reload];
}


/// Updates the header of the outline view as appropriate
-(void) updateHeader {
	/// we hide the header if we don't show individual (none stacked) samples, as the normal row views (those will columns) are not shown)
	traceOutlineView.headerView.hidden = self.showMarkers || (self.stackMode == stackModeSamples && !self.showGenotypes);
	NSInteger count = self.contentArray.count;
	self.stackedSampleTextfield.hidden = self.stackMode != stackModeSamples || self.showMarkers || self.showGenotypes || count < 2;
	if(!self.stackedSampleTextfield.hidden) {
		NSString *stringToShow = [NSString stringWithFormat:@"%ld samples stacked", count];
		if(count > 400) {
			stringToShow = [stringToShow stringByAppendingString:@" (400 shown)"];
		}
		self.stackedSampleTextfield.stringValue = stringToShow;
	}
}


/// reloads the outline view with new contents
- (void)reload {
	[traceOutlineView reloadData];
	[traceOutlineView expandItem:nil expandChildren:YES];
	[self updateHeader];
	
	/// We adjust the row height to the new content, so that the trace rows fill the visible area considering the possible change in the proportion of non-trace rows
	/// We do it after some delay to make sure the outline view has finished reloading.
	/// Otherwise, the row height change animation context is used by the traceView, which animate their zoom and scrolling to their final position, which is visually disturbing.
	/// Setting an NSAnimationContext grouping within the methods called by reloadData does not prevent that, maybe because the reload occurs before the change in row height.
	/// If reloadData occurred during or after, this would prevent the row height animation
	[self performSelector:@selector(adjustRowHeight) withObject:nil afterDelay:0.01];
}

-(void)loadContent:(NSButton *)sender {
	[self loadContentArray: MainWindowController.sharedController.sourceController.tableContent.selectedObjects];
}

#pragma mark - adding, removing, resizing rows


- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
	if ([item isKindOfClass: Chromatogram.class] | [item isKindOfClass: Genotype.class] ) {
		///when the element is a chromatogram or genotype, the height of the row showing its metadata is fixed
		return defaultRowHeight;
	}
	return self.traceRowHeight;
}


- (float)traceRowHeight {
	if(_traceRowHeight < minTraceRowHeight) {
		[self updateTraceRowHeight];
	}
	return _traceRowHeight;
}


/// updates the row height given the number of traces the user wants to see and the window height
- (void)updateTraceRowHeight {
	NSUInteger traceRowsPerWindow = self.numberOfRowsPerWindow;

	NSInteger numOtherRows = 0;					/// we compute the number of non-trace rows that should be visible
	if(self.showGenotypes || self.stackMode == stackModeChannels ) {
		/// if we show genotypes (which have just one trace) or if we stack channels, the are as numerous as trace views
		numOtherRows = traceRowsPerWindow;
	} else if(self.stackMode == stackModeSamples || self.showMarkers) {
		numOtherRows = 0;
	} else {
		/// if we don't stack channels, we have this estimate (we can't exactly fit all traces in this situation,
		/// as sometimes the view would show a sample row, sometimes not, depending on the scrolling position)
		/// + 0.9 rounds the result
		numOtherRows = traceRowsPerWindow / self.displayedChannels.count + 0.9;
		
	}
	
	NSInteger totRows = traceRowsPerWindow + numOtherRows;
	/// the height is computed so the number of rows fits the visible rect of the table
	/// we don't use the visibleRect as it appears to consider the area behind the header if the outline view is scrolled down. We use its clipView instead
	float proposedHeight = (traceOutlineView.superview.bounds.size.height - traceOutlineView.headerView.bounds.size.height - traceOutlineView.intercellSpacing.height*totRows - numOtherRows * defaultRowHeight) / traceRowsPerWindow;
	//// It is important to return a rounded height. Otherwise, some view' frames might not start/end at pixel boundaries,
	/// which results in fuzzy rendering and slightly misplaced elements
	proposedHeight = round(proposedHeight);
	if (proposedHeight < minTraceRowHeight) {
		proposedHeight = minTraceRowHeight;
	}
	self.traceRowHeight = proposedHeight;
}


- (void)windowDidResize:(NSNotification *)notification {
	/// the height of trace rows must be proportional to the visible area of the view
	/// we update it during window resizing
	[self resizeRows:nil];
}


- (void)setNumberOfRowsPerWindow:(NSUInteger)numberOfRowsPerWindow {
	if(numberOfRowsPerWindow < 1) {
		numberOfRowsPerWindow = 1;
	} else if(numberOfRowsPerWindow > 5) {
		numberOfRowsPerWindow = 5;
	}
	_numberOfRowsPerWindow = numberOfRowsPerWindow;
	if(self.contentArray) {
		[self resizeRows:self];
	}
}


///resizes the rows showing traces when the users adjusts the slider (sender) or resizes the window (sender = nil in this case)
- (IBAction)resizeRows:(id)sender {
	float currentHeight = self.traceRowHeight;
	[self updateTraceRowHeight];
	if(currentHeight == self.traceRowHeight) {
		/// when the window is resized only horizontally, the row height should not change, and it is better to return.
		/// If we don't, the pointless animation interferes with the resizing of trace views
		return;
	}
	/// This method also scrolls the table so that the position of the topmost visible row edge doesn't change
	/// If we didn't scroll, the change in row height would result in traces moving down as they get taller, or up as they get shorter, which would be disturbing, especially during window resizing.
	/// to achieve this, we need to identify the first row whose top is visible
	/// we compute the difference in height due to resizing of the trace views above this row
	/// and we scroll the outline view by this difference (positive or negative)
	__block float minY = currentHeight;
	__block NSInteger rowsAbove = 0;
	[traceOutlineView enumerateAvailableRowViewsUsingBlock:^(__kindof NSTableRowView * _Nonnull rowView, NSInteger row) {
		float y = NSMinY(rowView.frame) - NSMinY(traceOutlineView.visibleRect); /// this tells which rows has its top edge that is the closest from the top (and not hidden)
		if(y < minY && y >= 0) {
			minY = y;
			rowsAbove = [traceOutlineView rowForView:rowView];
		}
	}];
	
	/// we deduce the number of traces views above this first row from the number of standard (non-trace) rows
	NSInteger numStandardRows = self.contentArray.count;
	if((self.stackMode == stackModeSamples && !self.showGenotypes) || self.showMarkers) {
		numStandardRows = 0;
	}
	
	long totRows = traceOutlineView.numberOfRows;
	float traceRowAbove = 0;
	if(totRows > 0) {
		traceRowAbove = rowsAbove * (totRows - numStandardRows)/totRows;
	}
	float traceRowHeightAbove = traceRowAbove * currentHeight;						/// the total height they represent
	float heightDiff = traceRowAbove  * self.traceRowHeight - traceRowHeightAbove;		/// and the difference in height after they are resized
	
	[traceOutlineView beginUpdates];
	NSAnimationContext *context = NSAnimationContext.currentContext;
	if(sender == nil) {
		context.duration = 0.0;					/// we don't animate during live resize
		context.allowsImplicitAnimation = NO;
	}
	
	[traceOutlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,totRows)]];  /// this calls the -outlineView:heightOfRowByItem: method
	
	if(heightDiff != 0) {			/// we scroll the view by modifying its clipview's bounds origin (which is animatable)
		NSPoint origin = traceOutlineView.superview.bounds.origin;
		origin.y += heightDiff;		/// this will be the new origin
									/// we make sure that we can scroll to this new origin. Appkit refuses to do it if the outline view is not tall enough (it doesn't yet have its final size).
		if(traceOutlineView.frame.size.height < origin.y + traceOutlineView.visibleRect.size.height) {
			/// if it's not tall enough, we resize it (without animation).
			[traceOutlineView setFrameSize:NSMakeSize(traceOutlineView.frame.size.width, origin.y + traceOutlineView.visibleRect.size.height)];
		}
		[NSAnimationContext beginGrouping];					/// we scroll synchronously with the row height animation. The grouping prevents certain rows from flying around
		context.allowsImplicitAnimation = sender != nil;  	/// we don't animate the scroll during window resizing.
		[traceOutlineView.superview setBoundsOrigin:NSMakePoint(origin.x, origin.y)]; /// we don't use the animator proxy, as it results in jerky scrolling.
		[NSAnimationContext endGrouping];
	}
	[traceOutlineView endUpdates];
	
}


-(void)adjustRowHeight {	/// changes row height according to the current state of the table and the dimensions, but without trying to compensate the scroll position
	float previousHeight = self.traceRowHeight;
	[self updateTraceRowHeight];
	if(previousHeight != self.traceRowHeight && traceOutlineView.numberOfRows > 0) {
		[traceOutlineView beginUpdates];
		[traceOutlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, traceOutlineView.numberOfRows)]];
		[traceOutlineView endUpdates];
	}
}


/// Reveals or hides rows showing particular channels, with animation.
- (void)colorsToHide:(NSIndexSet*)rowsToRemove colorsToReveal:(NSIndexSet*) rowsToInsert {
	if (self.showGenotypes || self.showMarkers) {
		/// this is a safety measure, as this method should not be called in these situations
		return;
	}
	NSArray *parents = self.contentArray;						/// the "parents" are samples in which to hide or reveal traces of different colors
	NSInteger totRow = traceOutlineView.numberOfRows;
	/// as a safety measure, we count the number of visible rows per parent to avoid hiding rows that aren't there.
	/// We to these checks as we often got errors where we would remove or add rows in parents that don't have the correct number of children (for undetermined reasons)
	/// We don't use -numberOfChildOfItem: because it is not based on the current outline view state, but on what it *should* be, based on the number of channels that are visible (which, at this stage, isn't reflected yet in view. This is what this method is about).
	NSInteger nrowPerParent = totRow;
	
	if (self.stackMode == stackModeSamples) {		/// in case all samples show in the same row (with just one row per color in total)
		if(parents.count == 0) {
			return;				/// if no sample is shown, we return as the colors can't be associated with rows
		}
	} else {
		int nVisible = 0;							/// to count the number of visible rows (traces) per sample, we must consider collapsed items (note: we don't currently allow collapsing anyway)
		for(id parent in parents) {
			if ([traceOutlineView isItemExpanded:parent]) {
				nVisible++;
			}
		}
		if(nVisible == 0) {
			[traceOutlineView reloadData];
			return;					/// if all samples are collapsed, there is nothing to animate (and the instruction below would cause a crash)
		}
		nrowPerParent = (totRow - parents.count) / nVisible;
		/// we assume this ratio to be round. if not, it means there a bug somewhere else as all samples should show the same number of rows (even if some rows show no fluorescence data)
	}
	
	/// we now check if the rows to hide are among the visible rows and the rows to show are among the possible rows to reveal
	NSIndexSet *visibleRows = [NSIndexSet indexSet];
	if(nrowPerParent > 0) {
		visibleRows = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, nrowPerParent)];
	}
	NSIndexSet *possibleRows = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 5)];		/// the possible row indices to reveal simply correspond to the number of channels, 0..4
	if(! ([visibleRows containsIndexes:rowsToRemove] && [possibleRows containsIndexes:rowsToInsert])) {		/// if the conditions are not met, we just reload the table.
		[traceOutlineView reloadData];
		NSLog(@"Rows to hide or reveal don't fit with available rows. Animation stopped");
		return;
	}
	
	/// if we are here, it should be safe to reveal or hide channels with animation
	/// note: the app initially implemented a much simpler method without all these checks and which basically started here
	/// but it sometimes caused crashes because it would somehow try to hide or show a child row that is out of range.
	
	[traceOutlineView beginUpdates];
	
	if(self.stackMode == stackModeSamples) {
		[traceOutlineView removeItemsAtIndexes:rowsToRemove inParent:nil withAnimation:NSTableViewAnimationSlideUp];
		[traceOutlineView insertItemsAtIndexes:rowsToInsert inParent:nil withAnimation:NSTableViewAnimationSlideDown];
		
	} else for(id parent in parents) {
		[traceOutlineView removeItemsAtIndexes:rowsToRemove inParent:parent withAnimation:NSTableViewAnimationSlideUp];
		[traceOutlineView insertItemsAtIndexes:rowsToInsert inParent:parent withAnimation:NSTableViewAnimationSlideDown];
	}
	[self updateTraceRowHeight];
	[traceOutlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, traceOutlineView.numberOfRows)]];
	
	[traceOutlineView endUpdates];
	
}



- (void)setStackMode:(StackMode)stackMode {
	if(self.stackMode == stackMode) {
		return;
	}
	StackMode previous = self.stackMode;
	_stackMode = stackMode;
	if(!self.showGenotypes && !self.showMarkers) {
		if(previous == stackModeSamples || stackMode == stackModeSamples) {
			[self reload];
		} else {
			[self stackChannels];
		}
	}
}


#pragma mark - management of colors to show


- (NSArray <NSNumber *> *)displayedChannels {
	if(_displayedChannels) {
		return _displayedChannels;
	}
	[self setDisplayedChannels];
	return _displayedChannels;
}


- (void)setDisplayedChannels {
	int nChannels = 5;
	if(self.contentArray.count > 0 && [self.contentArray.firstObject isKindOfClass:Chromatogram.class]) {
		nChannels = 4;
		for(Chromatogram *sample in self.contentArray) {
			if(sample.traces.count > 4) {
				nChannels = 5;
				break;
			}
		}
		if(nChannels == 4) {
			if(self.displayedChannels.count == 1 && [NSUserDefaults.standardUserDefaults boolForKey:ShowChannel4]) {
				[NSUserDefaults.standardUserDefaults setBool:YES forKey:ShowChannel3];
			}
			[NSUserDefaults.standardUserDefaults setBool:NO forKey:ShowChannel4];
		}
	}
	
	NSMutableArray *newDisplayedChannels = [NSMutableArray arrayWithCapacity:5];  /// we update the channels to display
	for (int channel = 0; channel < 5; channel++) {
		if ([NSUserDefaults.standardUserDefaults boolForKey:channelPreferenceKeys[channel]])
			[newDisplayedChannels addObject:@(channel)];
	}
	
	self.displayedChannels = newDisplayedChannels;

	for (NSButton *button in channelButtons) {
		button.enabled = button.tag < nChannels && !(button.state == NSControlStateValueOn && self.displayedChannels.count == 1);
	}
}


/// message sent by buttons that show/hide channels
- (IBAction)channelsToShow:(NSButton*)sender {
	NSArray *oldDisplayedChannels = self.displayedChannels;
	/// we keep a reference of the channels previously displayed, as we make some animations inserting/removing rows when the displayed channels change
	BOOL altKeyDown = (NSApp.currentEvent.modifierFlags & NSEventModifierFlagOption) != 0;
	///if alt key is pressed, we will only show the channel associated with the button that was clicked, regardless of its previous state
	if (altKeyDown) {
		for (int channel = 0; channel <= 4; channel++) {
			[NSUserDefaults.standardUserDefaults setBool:NO forKey:channelPreferenceKeys[channel]]; /// we first deselect all channels
		}
		[NSUserDefaults.standardUserDefaults setBool:YES forKey:channelPreferenceKeys[sender.tag]]; ///and enable the channel corresponding to the button tag
	}
	[self setDisplayedChannels];
	
	[self updateViewGivenOldDisplayedDies:oldDisplayedChannels];
}



- (void)updateViewGivenOldDisplayedDies:(NSArray *)oldDisplayedDies {
	if (self.stackMode != stackModeChannels && self.contentArray.count > 0) {
		if(self.contentArray.count < 100) {	/// if the number of item is not to high, we may hide/reveal channels with animation
			if(oldDisplayedDies.count == self.displayedChannels.count) {		/// if the number of visible channels did not change we just reload the outline view
				[traceOutlineView reloadData];
				return;
			}
			/// else we reveal/hide rows with animation.
			NSIndexSet *rowsToRemove = [oldDisplayedDies indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
				return ![self.displayedChannels containsObject:obj];  		/// gets the index of channels that should be hidden
			}];
			
			NSIndexSet *rowsToInsert = [self.displayedChannels indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
				return ![oldDisplayedDies containsObject:obj];  			/// gets the index of channels that should now be revealed
			}];
			
			[self colorsToHide:rowsToRemove colorsToReveal:rowsToInsert]; 	///actual method that removes/inserts rows
		} else {
			[self reload];
		}
	}
}


- (void)stackChannels { /// this stacks the visible channels of each sample in a single row or does the reverse
	/// we should never stack channels when samples are stacked, genotypes or markers are shown (the menus or buttons for that should be disabled in this case, but this is a safety measure).
	if(self.stackMode == stackModeSamples || self.showGenotypes || self.showMarkers) {
		return;
	}
	
	if(self.displayedChannels.count == 0 || self.contentArray.count > 100) {
		/// when there are many items, we just reload the table (for performance reasons)
		[self reload];
		return;
	}
	/// otherwise, we do some animation
	NSIndexSet *rowsForSeparateChannels = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, self.displayedChannels.count-1)]; ///indexes of rows that correspond to separate channels except the first one (which will hold the stacked curves)
	if (self.stackMode == stackModeChannels) {
		/// Here, we stack channels in a single row per sample
		/// even if colorsToHide:colorsToReveal: calls beginUpdates, we must wrap all updates,
		/// otherwise the outline view may spawn a row view for a row that becomes visible during animation,
		/// even though this row is among those that should be removed, which creates a bug.
		[traceOutlineView beginUpdates];
		[self refreshFirstRows];		/// we refresh the rows showing the stacked trace for each sample.
										/// We do it before removing other rows for better visual result
		[self colorsToHide:rowsForSeparateChannels colorsToReveal:NSIndexSet.new]; /// we remove the rows for separate channels with animation
		[traceOutlineView endUpdates];
	} else {                            		/// if we should "unstack" channels…
		[traceOutlineView beginUpdates];
		[self refreshFirstRows];
		[self colorsToHide:NSIndexSet.new colorsToReveal:rowsForSeparateChannels];
		[traceOutlineView endUpdates];
	}
}

/// Replaces the first row/trace for each sample with another row, forcing it to reload its content.
/// Perhaps not very elegant, but the outline view -reload methods actually doesn't update the row views (just cell views), except -reloadData, which would stop the animation of all rows. Plus, we can use a fade effect
- (void)refreshFirstRows {
	if(self.displayedChannels.count == 0) return;
	for (id sample in self.contentArray) {
		[traceOutlineView beginUpdates];
		[traceOutlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:0] inParent:sample withAnimation:NSTableViewAnimationEffectFade];
		[traceOutlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:0] inParent:sample withAnimation:NSTableViewAnimationEffectFade];
		[traceOutlineView endUpdates];
		
	}
}

#pragma mark - column management

- (CGFloat)outlineView:(NSOutlineView *)outlineView sizeToFitWidthOfColumn:(NSInteger)column {
	return [super tableView:outlineView sizeToFitWidthOfColumn:column];
}


#pragma mark - delegate methods for traceViews

- (BaseRange)visibleRangeForTraceView:(TraceView *)traceView {
	/// if we should synchronize visible ranges, we return the value we have recorded
	if (self.synchronizeViews && referenceRange.len > 0) {
		return  referenceRange;
	}
	
	/// else  we use the range of a view's trace, as the user would want the traces to appear where they were left
	BaseRange refRange = MakeBaseRange(-1.0, -1.0);
	for (Trace *trace in traceView.loadedTraces) {
		///if the view shows traces from different channels (hence shows a sample), we use the range of the *visible* trace with lowest channel. This creates a better visual effect when the stack channels button is pressed
		if(traceView.channel || [self.displayedChannels containsObject: @(trace.channel)]) {
			refRange = trace.visibleRange;
			break;
		}
	}
	
	if(refRange.len <= 0) {
		/// which would be the case if no trace of the view bas been displayed yet. In this case we use the defaults
		refRange = traceView.defaultRange;
	}
	return refRange;
}


- (float)topFluoLevelForTraceView:(TraceView *)traceView {
	if (self.topFluoMode == topFluoModeSynced) {
		return referenceTopFluoLevel;
	} else {
		float fluo = traceView.genotype.topFluoLevel;
		if (fluo > 0.0) {
			return fluo;
		} else {
			fluo = traceView.trace.topFluoLevel;
			if(fluo > 0.0) {
				return fluo;
			}
		}
	}
	
	return 0.0;
}




- (void)traceViewDidChangeRangeVisibleRange:(TraceView *)traceView {
	if (self.synchronizeViews && !self.showGenotypes && !self.showMarkers) {
		BaseRange range = traceView.visibleRange;
		for(TraceView *aTraceView in traceViews) {
			if(aTraceView != traceView) {
				[aTraceView setVisibleRangeAndDontNotify:range];
			}
		}
		referenceRange = range;
	}
}


- (void)traceViewDidChangeTopFluoLevel:(TraceView *)traceView{
	if (self.topFluoMode == topFluoModeSynced) {
		float fluo = traceView.topFluoLevel;
		for(TraceView *aTraceView in traceViews) {
			if(aTraceView != traceView) {
				[aTraceView setTopFluoLevelAndDontNotify:fluo];
			}
		}
		referenceTopFluoLevel = fluo;
	}
}


- (void)traceView:(TraceView *)traceView didStartMovingToRange:(BaseRange)range {
	if (!self.showGenotypes && !self.showMarkers && self.topFluoMode == topFluoModeHighestPeak && self.synchronizeViews ) {
		/// if a view starts moving , if sync is on and if traceViews auto scale of their highest peak,
		/// we animate the vertical scale so that it changes during the move (and not after)
		for(TraceView *aTraceView in traceViews) {
			if(aTraceView != traceView) {
				float targetFluo = [aTraceView topFluoForRange:range];
				if(targetFluo > 0) {
					aTraceView.animator.topFluoLevel = targetFluo;
				}
			}
		}
	}
}


- (void)setTopFluoMode:(TopFluoMode)topFluoMode {
	_topFluoMode = topFluoMode;
	self.autoScaleToHighestPeak = topFluoMode == topFluoModeHighestPeak;
}


- (void)setDefaultStartSize:(float)defaultStartSize {
	_defaultStartSize = defaultStartSize;
	self.defaultRange = MakeBaseRange(defaultStartSize, self.defaultEndSize-defaultStartSize);
}


- (void)setDefaultEndSize:(float)defaultEndSize {
	_defaultEndSize = defaultEndSize;
	self.defaultRange = MakeBaseRange(self.defaultStartSize, defaultEndSize-self.defaultStartSize);
}

@end

