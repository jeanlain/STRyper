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
#import "Mmarker.h"
#import "MainWindowController.h"
#import "SampleTableController.h"
#import "MarkerView.h"
#import "TraceScrollView.h"
#import "STableRowView.h"
#import "RulerView.h"
#import "SizeStandardTableController.h"
#import "SizeStandard.h"
#import "TraceOutlineViewPrinter.h"
#import "Allele.h"
#import "PanelListController.h"

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

/// read-write implementations of the readonly public properties.
@property (nonatomic) BOOL showGenotypes;
@property (nonatomic) BOOL showMarkers;

/// A button that we may show to ask the user for confirmation to load a large number or samples or genotypes in the outline view
@property (nonatomic) NSButton *loadContentButton;

/// A textfield indicating the number of stacked samples or genotypes that are shown, instead of the table header view
@property (nonatomic) NSTextField *stackedSampleTextfield;

/// The channels (as integers) that are currently displayed when the detailed view shows traces.
@property (nonatomic) NSArray<NSNumber *> *displayedChannels;

/// the height of rows showing traces views.
@property (nonatomic) CGFloat traceRowHeight;

@end



@implementation DetailedViewController

/// Notes on the implementation:
/// The "detail(ed) view" is an outline view, as we convey the hierarchy between two entities:
/// ``Chromatogram``/``Genotype`` objects , which are represented as regular rows, as in the sample table. They are the "parents".
/// The children are the chromatograms' traces (``Trace`` class), which show in custom row views harboring trace views.
/// These row views don't have any table cell views.
///
/// This hierarchy facilitates the managing of the data source and showing/hiding channels.
///
/// When samples are shown (i.e., selected in the source table), there are several display modes (see StackMode typdef)
/// When genotypes are shown (and not stacked), a regular row showing samples information in several column is followed by a child row showing the trace of the sample at the corresponding marker.
/// When genotypes are shown and stacked, there is one row per molecular marker, showing a trace view (in which alleles are shown as dots).
/// When markers are shown, one tall row per marker shows bins and the marker range (like in genotype mode when bin editing is enabled, but without the trace behind).
///
/// We don't use many of the TableViewController methods as the user cannot select nor remove items from the outline view/

{
	NSArray<NSNumber *> *previousDisplayedChannels;			/// The displayed channels before a change in the property. Required for animating the change.
	StackMode previousStackMode;					/// The stackMode before a change in the property. Required for animating the change.
	
	NSArray<NSButton *> *channelButtons;	/// array containing references to the round buttons allowing to show/hide channels.
											/// We use this array for quicker access as there are other buttons
	
	NSSegmentedControl *stackSegmentedControl; /// The control for the stack mode.
	
	__weak TraceOutlineView *traceOutlineView;  /// the "detailed view", of which this object is the delegate and which is also the view it controls
	
	BaseRange referenceRange;				/// the synchronized visible range of traceViews
	float referenceTopFluoLevel;			/// the synchronize top fluo level of traceViews
	
	NSMutableSet<TraceView *> *traceViews;	/// the set of visible trace views that we use to synchronize them
											/// I believe it is faster than enumerating all rows of the outline view at each scroll step
	
	__weak TraceView *traceViewForMenu;
	
	/// A row view that is reused during printing.
	STableRowView *printedTraceRowView;
	NSTableRowView *printedStandardRowView;
	NSTableRowView *printedNoTraceRowView;

	NSArray<Mmarker *> *loadedMarkers;     /// Markers of loaded genotypes, which we use when `stackGenotypes` is YES.
}

@synthesize traceRowHeight = _traceRowHeight;

static NSArray<NSString *> *channelPreferenceKeys,
*channelPreferenceKeysG;				/// convenience arrays we use to bind values of channel buttons to the corresponding user default key and to determine which button to disable
																
static NSString* const applySizeStandardMenuIdentifier = @"applySizeStandardMenuIdentifier";
static NSString* const applyPanelMenuIdentifier = @"applyPanelMenuIdentifier";


static const CGFloat defaultRowHeight = 20.0;
static const CGFloat minTraceRowHeight = 40.0;
static const CGFloat maxTraceRowHeight = 1000.0;


+ (instancetype)sharedController {
	static DetailedViewController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = self.new;
	});
	return controller;
}


- (NSNibName)nibName {
	return @"RightPane";
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
	return nil; /// We don't use an NSArray/tree controller to manage the view's content
}


- (void)viewDidLoad {
	channelPreferenceKeys = @[ShowChannel0, ShowChannel1, ShowChannel2, ShowChannel3, ShowChannel4];
	channelPreferenceKeysG = @[ShowChannel0G, ShowChannel1G, ShowChannel2G, ShowChannel3G, ShowChannel4G];

	NSMutableArray *channelButtonArray = NSMutableArray.new;
	
	[self.tableView bind:NSSortDescriptorsBinding toObject:SampleTableController.sharedController.samples withKeyPath:NSStringFromSelector(@selector(sortDescriptors)) options:nil];
	
	NSUserDefaults *standardUserDefaults = NSUserDefaults.standardUserDefaults;
	
	/// we bind the contents to show in the detailed view to the selected objects of the source controller.
	/// The detailed view will then show the selected objects from the various sources
	[self bind:ContentArrayBinding toObject:MainWindowController.sharedController withKeyPath:@"sourceController.tableContent.selectedObjects" options:nil];
	[self bind:NSStringFromSelector(@selector(stackMode))
	  toObject:standardUserDefaults withKeyPath:TraceStackMode options:nil];
	[self bind:NSStringFromSelector(@selector(numberOfRowsPerWindow)) 
	  toObject:standardUserDefaults withKeyPath:TraceRowsPerWindow options:nil];
	[self bind:NSStringFromSelector(@selector(synchronizeViews)) 
	  toObject:standardUserDefaults withKeyPath:SynchronizeViews options:nil];
	[self bind:NSStringFromSelector(@selector(topFluoMode)) 
	  toObject:standardUserDefaults withKeyPath:TraceTopFluoMode options:nil];

	/// we apply bindings to the display buttons
	/// we make an array of some preferences keys to bind to some buttons, based on the button tags (used to fetch the corresponding key in the array):
	NSArray *prefKeys = @[TraceTopFluoMode, SynchronizeViews, ShowOffScale, ShowBins, TraceStackMode];
	for (NSControl *control in self.view.subviews) {
		if([control isKindOfClass: NSButton.class] || [control isKindOfClass: NSSegmentedControl.class]) {
			/// all buttons must be hidden when the outline view shows markers, except the slider that controls row height
			[control bind:NSHiddenBinding toObject:self withKeyPath:NSStringFromSelector(@selector(showMarkers)) options:nil];
			if(control.tag < 5 && control.tag >=0) {
				/// these are buttons controlling the channel to show. Their tags represent the channels from 0 to 4.
				[channelButtonArray addObject:control];
			}
			if(control.tag < 0) {
				if([control isKindOfClass: NSButton.class]) {
					NSString *keyPath = prefKeys[-control.tag -1];
					[control bind:NSValueBinding toObject:standardUserDefaults withKeyPath:keyPath options:nil];
					if([keyPath isEqualToString:SynchronizeViews]) {
						/// The button that controls the horizontal synchronization is disabled when genotypes are shown.
						[control bind:NSEnabledBinding toObject:self
						  withKeyPath:NSStringFromSelector(@selector(showGenotypes))
							  options:@{NSValueTransformerNameBindingOption:NSNegateBooleanTransformerName}];
					}
				} else if([control isKindOfClass: NSSegmentedControl.class]) {
					if(control.tag == -1) {
						[control bind:NSSelectedIndexBinding toObject:standardUserDefaults withKeyPath:TraceTopFluoMode options:nil];
					} else if(control.tag == -5) {
						stackSegmentedControl = (NSSegmentedControl *)control;
						[self configureStackSegmentedControl];
					}
				}
			}
		} else if([control isKindOfClass:NSSlider.class]) {
			[control bind:NSValueBinding toObject:standardUserDefaults withKeyPath:TraceRowsPerWindow options:nil];
		}
	}
	
	channelButtons = channelButtonArray.copy;
	[self updateChannelButtons];
	
	traceOutlineView = (TraceOutlineView *)self.tableView;
	traceOutlineView.backgroundColor = [NSColor colorNamed:ACColorNameViewBackgroundColor];
	
	[super viewDidLoad];
	
	/// We make sure the sample name column is column 0
	int i = 0;
	for(NSTableColumn *column in traceOutlineView.tableColumns) {
		if([column.identifier isEqualToString:@"sampleNameColumn"]) {
			if(i != 0) {
				[traceOutlineView moveColumn:i toColumn:0];
			}
			break;
		}
		i++;
	}
	
	[self bind:NSStringFromSelector(@selector(defaultStartSize)) toObject:standardUserDefaults withKeyPath:DefaultStartSize options:nil];
	[self bind:NSStringFromSelector(@selector(defaultEndSize)) toObject:standardUserDefaults withKeyPath:DefaultEndSize options:nil];
	
	/// we set the default visible range of trace views
	referenceRange = MakeBaseRange(-1, -1);
	float start = [standardUserDefaults floatForKey:ReferenceStartSize];
	float end = [standardUserDefaults floatForKey:ReferenceEndSize];
	if(end > 0) {
		referenceRange = MakeBaseRange(start, end - start);
	}
	
	referenceTopFluoLevel = -1.0;
	
	traceViews = NSMutableSet.new;
}



- (NSButton *)loadContentButton {
	if(!_loadContentButton && traceOutlineView.superview) {
		/// we place the button asking for confirmation to load the content at the center of the visible rectangle of the outline view, i.e at the center of the scroll view.
		/// placing it in the enclosing scrollview works does not allow using layout constraints.
		NSView *scrollView = traceOutlineView.superview.superview;;
		_loadContentButton = [traceOutlineView makeViewWithIdentifier:@"loadContentButton" owner:self];
		_loadContentButton.translatesAutoresizingMaskIntoConstraints = NO;
		[scrollView.superview addSubview:_loadContentButton];
		/// we center the button horizontally and vertically in its view
		[_loadContentButton.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor].active = YES;
		[_loadContentButton.bottomAnchor constraintEqualToAnchor:scrollView.centerYAnchor].active = YES;
		_loadContentButton.target = self;
		_loadContentButton.action = @selector(confirmLoadContent:);
		_loadContentButton.keyEquivalent = @"\r";
		
	}
	return _loadContentButton;
}


- (NSTextField *)stackedSampleTextfield {
	if(!_stackedSampleTextfield && traceOutlineView.headerView) {
		_stackedSampleTextfield = [NSTextField labelWithString:@"Several samples stacked"];
		
		/// we place the text field over the header view, i.e. at the top of the enclosing scroll view of the traceOutlineView.
		/// We don't place it within the clip view, and we don't want it to scroll. Placing it inside the scroll view does not work with layout constraints.
		NSScrollView *scrollView = traceOutlineView.enclosingScrollView;
		_stackedSampleTextfield.translatesAutoresizingMaskIntoConstraints = NO;
		[scrollView.superview addSubview:_stackedSampleTextfield];
		[_stackedSampleTextfield.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor].active = YES;
		
		/// We center it vertically at the middle of the header view.
		NSTableHeaderView *headerView = traceOutlineView.headerView;
		[_stackedSampleTextfield.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor].active = YES;
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
	StackMode stackMode = self.stackMode;
	BOOL showGenotypes = self.showGenotypes;
	if (item == nil) {
		NSArray *contentArray = self.contentArray;
		NSInteger itemCount = contentArray.count;		/// the number of parent rows is by default the number of items in the content array
		if(itemCount == 0) {
			return 0;
		}
		if(showGenotypes && self.stackGenotypes) {
			return loadedMarkers.count;
		}
		return (stackMode == stackModeSamples && itemCount > 1 && !showGenotypes && !self.showMarkers)? self.displayedChannels.count : itemCount;  /// if we stack sample curves, the number of rows is the number of channels to show
	}
	if([item isKindOfClass: Genotype.class]) {
		return 1;	/// a genotype has one child, which is the trace corresponding to the marker's channel for the chromatogram
	}
	
	if([item isKindOfClass: Chromatogram.class]) {
		/// the number of children of a chromatogram depends on whether the channels are stacked or not
		return (stackMode == stackModeChannels && !showGenotypes)? 1 : self.displayedChannels.count;  /// which is the number of rows in each sample (1 if channels overlap, or the number of channels to show separately, depending on the view setting)
	}
	return 0;	/// other types of items have no children as they are represented by trace rows. They are not expandable.
}


- (id) outlineView:(id)outlineView child:(NSInteger)index ofItem:(id)item {
	NSInteger itemCount = self.contentArray.count;
	StackMode stackMode = self.stackMode;
	BOOL showGenotypes = self.showGenotypes;
	NSArray<NSNumber *> *displayedChannels = self.displayedChannels;
	
	if (item == nil) {  /// the top-level rows
		if (stackMode == stackModeSamples && itemCount > 1 && !showGenotypes && !self.showMarkers) {
			/// If samples are stacked, each row shows traces for a displayed channel.
			if(index < displayedChannels.count) {
				return [self tracesForChannel:displayedChannels[index].intValue];
			}
		} else if(self.stackGenotypes && showGenotypes) {
			/// Here, each row will show all genotypes of a marker
			if(index < loadedMarkers.count) {
				Mmarker *marker = loadedMarkers[index];
				return [self.contentArray filteredArrayUsingBlock:^BOOL(Genotype *genotype, NSUInteger idx) {
					return genotype.marker == marker;
				}];
			}
		} else {
			/// If we don't stack items in the same row, we simply return the item at the corresponding index in the content array
			/// This must be a chromatogram, a marker, or a genotype
			if(index < itemCount) {
				return self.contentArray[index] ;
			}
		}
	} else if([item isKindOfClass:Genotype.class]) {
		/// When the parent is a genotype, the (only) child row should load the genotype itself (see TraceView.h)
		/// but if we returned the genotype, it would be identical to the parent (causing an infinite loop).
		/// So we encapsulate the genotype in an NSSet, to differentiate from the case where we stack genotypes (in an array).
		return [NSSet setWithObject:item];
	} else if([item isKindOfClass:Chromatogram.class]) {
		if(stackMode == stackModeChannels) {
			/// Here we stack all traces of a chromatogram in the (only) child row.
			return ((Chromatogram *)item).traces.allObjects;
		}
		/// If we don't stack channels, each child row shows the trace of a given channel.
		if(index < displayedChannels.count) {
			Trace *trace =[item traceForChannel: displayedChannels[index].intValue];	/// the child row will show the sample's trace for the correct channel
			if(trace) {
				/// A trace view does not load trace objects, only array of traces.
				return @[trace];
			}
		}
	}
	return  NSNull.null; /// This should happen (normally) only if there is no trace for the orange channel and this channel is among those we display.
						 /// The null object will be interpreted as the need to show a row signifying that.
						 
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
	return item;
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
	
	///otherwise, the row should show a trace view that will load traces, genotypes, or a marker
	return [self outlineView:outlineView traceRowViewForItem:item printing:NO];
}


-(STableRowView *) outlineView:(NSOutlineView *)outlineView traceRowViewForItem:(id)item printing:(BOOL) printing {
	
	if([item isKindOfClass:NSSet.class]) {
		/// Genotype objects are encapsulated as sole objects in an NSSet.
		item = [item anyObject];
	}
			
	STableRowView *rowView;
	TraceView *traceView;
	rowView = printing? printedTraceRowView : [self rowViewForItem:item];
	
	/// We set the frame (size) of the row view (before the outline view would do it) to avoid successive resizing of a trace view that has content loaded.
	NSRect frame = NSMakeRect(0, 0, outlineView.bounds.size.width, self.traceRowHeight + outlineView.intercellSpacing.height);
	
	if(rowView) {
		if(fabs(rowView.frame.size.height - frame.size.height) >= 1) {
			[rowView setFrameSize:frame.size];
		}
		NSScrollView *scrollView = rowView.mainSubview;
		if([scrollView respondsToSelector:@selector(documentView)]) {
			traceView = scrollView.documentView;
		}
	} else {
		rowView = [STableRowView.alloc initWithFrame:frame];
		TraceScrollView *scrollView = [[TraceScrollView alloc] initWithFrame:frame];
		scrollView.autoresizingMask = NSViewHeightSizable;
		if(printing) {
			scrollView.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
			scrollView.hasHorizontalScroller = NO; /// We don't print scrollers
		}
		rowView.mainSubview = scrollView;
		
		traceView = [[TraceView alloc] initWithFrame:frame];
		traceView.delegate = self;
		scrollView.documentView = traceView;

		NSUserDefaults *standardUserDefaults = NSUserDefaults.standardUserDefaults;
		[traceView bind:ShowBinsBinding toObject:standardUserDefaults withKeyPath:ShowBins options:nil];
		[traceView bind:ShowPeakTooltipsBinding toObject:standardUserDefaults withKeyPath:ShowPeakTooltips options:nil];
		[traceView bind:ShowOffScaleRegionsBinding toObject:standardUserDefaults withKeyPath:ShowOffScale options:nil];
		[traceView bind:ShowRawDataBinding toObject:standardUserDefaults withKeyPath:ShowRawData options:nil];
		[traceView bind:PaintCrosstalkPeakBinding toObject:standardUserDefaults withKeyPath:PaintCrosstalkPeaks options:nil];
		[traceView bind:MaintainPeakHeightsBinding toObject:standardUserDefaults withKeyPath:MaintainPeakHeights options:nil];
		[traceView bind:AutoScaleToHighestPeakBinding toObject:self withKeyPath:@"autoScaleToHighestPeak" options:nil];
		[traceView bind:IgnoreCrossTalkPeaksBinding toObject:standardUserDefaults withKeyPath:IgnoreCrosstalkPeaks options:nil];
		[traceView bind:IgnoreOtherChannelsBinding toObject:standardUserDefaults withKeyPath:IgnoreOtherChannels options:nil];
		[traceView bind:DisplayedChannelsBinding toObject:self withKeyPath:@"displayedChannels" options:nil];
		[traceView bind:DefaultRangeBinding toObject:self withKeyPath:@"defaultRange" options:nil];
		[scrollView bind:AllowSwipeBetweenMarkersBinding toObject:standardUserDefaults withKeyPath:SwipeBetweenMarkers options:nil];
		[scrollView bind:AlwaysShowsScrollerBinding toObject:standardUserDefaults withKeyPath:AlwaysShowScrollers options:nil];
		
			traceView.showDisabledBins = [standardUserDefaults boolForKey:ShowBins];
			traceView.showOffscaleRegions = [standardUserDefaults boolForKey:ShowOffScale];
			traceView.showRawData = [standardUserDefaults boolForKey:ShowRawData];
			traceView.paintCrosstalkPeaks = [standardUserDefaults boolForKey:PaintCrosstalkPeaks];
			traceView.maintainPeakHeights = [standardUserDefaults boolForKey:MaintainPeakHeights];
			traceView.autoScaleToHighestPeak = self.autoScaleToHighestPeak;
			traceView.ignoreCrosstalkPeaks = [standardUserDefaults boolForKey:IgnoreCrosstalkPeaks];
			traceView.ignoreOtherChannels = [standardUserDefaults boolForKey:IgnoreOtherChannels];
			traceView.displayedChannels = self.displayedChannels;
			traceView.defaultRange = self.defaultRange;
		
	}

	[traceView loadContent:item];
	
	if(printing) {
		if(!printedTraceRowView) {
			[self configureViewForPrinting:rowView];
			printedTraceRowView = rowView;
		}
	} 
	
	return  rowView;
}


/// Returns an appropriate rowView for an item shown in a ``TraceView``.
///
/// The returned row view has a trace view which has loaded the same panel as the item to show,
/// if such row view is available.
/// - Parameter item: The item to show in the row view.
- (STableRowView *)rowViewForItem:(id)item {
	STableRowView *rowView;
	Panel *panelToShow;
	ChannelNumber channelToShow = blueChannelNumber;
	if([item isKindOfClass:NSArray.class]) {
		id obj = [item firstObject];
		if([obj isKindOfClass:Trace.class] && ([item count] == 1 || self.stackMode != stackModeChannels)) {
			Trace *trace = (Trace *)obj;
			if(!trace.isLadder) {
				/// Note that several traces of the same channel may not correspond to samples
				/// analyzed at the same panel, but the trace view will check it anyway.
				panelToShow = trace.chromatogram.panel;
				channelToShow = trace.channel;
			}
		} else if([obj isKindOfClass:Genotype.class]) {
			item = obj;
		}
	}
	if([item isKindOfClass:Genotype.class]) {
		Mmarker *marker = ((Genotype *)item).marker;
		panelToShow = marker.panel;
		channelToShow = marker.channel;
	}
	
	if(panelToShow) {
		NSString *ID = [NSString stringWithFormat:@"%@ %@ %d", panelToShow.name, panelToShow.parent.name, channelToShow];
		rowView = [traceOutlineView makeViewWithIdentifier:ID owner:self];
	}
	if(!rowView) {
		rowView = [traceOutlineView makeViewWithIdentifier:@"traceRowView" owner:self];
	}
	return rowView;
}


- (void)outlineView:(NSOutlineView *)outlineView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
	if ([rowView.identifier isEqualToString:@"noTraceRowViewKey"])  {
		rowView.backgroundColor = NSColor.orangeColor;		/// setting this in `rowViewForItem:` has no effect, for some reason
	} else if ([rowView isKindOfClass:STableRowView.class]) {
		NSScrollView *scrollView = ((STableRowView *)rowView).mainSubview;
		TraceView *traceView = scrollView.documentView;
		if(traceView) {
			[traceViews addObject:traceView];
		}
	}
}


- (void)outlineView:(NSOutlineView *)outlineView didRemoveRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
	if ([rowView isKindOfClass:STableRowView.class]) {
		NSScrollView *scrollView = ((STableRowView *)rowView).mainSubview;
		TraceView *traceView = scrollView.documentView;
		if(traceView) {
			Panel *panel = traceView.panel;
			NSString *ID = @"traceRowView";
			if(panel && traceView.trace) {
				/// We give the row view an identifier that represents the panel and the channel of the trace view.
				/// If needed we can retrieve a view that has loaded a particular panel for a channel (see ``rowViewForItem:``).
				/// This allows the trace view (and marker view) to reuse labels for bins and markers, improving load time.
				ID = [NSString stringWithFormat:@"%@ %@ %d", panel.name, panel.parent.name, traceView.channel];
			}
			rowView.identifier = ID;
			[traceView prepareForReuse];
			[traceViews removeObject:traceView];
		}
	}
}


- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
	if (![item isKindOfClass: Chromatogram.class] && ![item isKindOfClass: Genotype.class]) {
		/// if the item isn't a Chromatogram or genotype the row has no cell (traces and markers are shown in the row view)
		return nil;
	}
	/// We generate a future identifier for the view to avoid configuring it several times
	NSString *ID = [tableColumn.identifier stringByAppendingString:@"_configured"];
	
	NSTableCellView *cellView = [outlineView makeViewWithIdentifier:ID owner:self];
	if(cellView) {
		return cellView;
	}
		
	if([tableColumn.identifier isEqualToString:@"sampleNameColumn"]) {
		/// For this column, the cell view prototype is different from that of the sample table.
		/// It has a button to allow revealing the represented item in the source list (sample table or genotype table)
		cellView = [outlineView makeViewWithIdentifier:@"sampleNameCellView" owner:self];
		if(cellView) {
			NSTextField *textField = cellView.textField;
			if(textField) {
				[textField bind:NSValueBinding toObject:cellView withKeyPath:@"objectValue.sampleName" options:@{NSValidatesImmediatelyBindingOption:@YES}];
			}
			NSButton *button = [cellView viewWithTag:1];
			if(button) {
				button.action = @selector(revealInList:);
				button.target = self;
				button.showsBorderOnlyWhileMouseInside = YES; /// This is the only reason why we configure this view in code,
															  /// The rest could have been configured in IB.
			}
			cellView.identifier = ID;
			return cellView;
		}
	}
	
	/// otherwise, we return table cells views whose prototype are in the sampleTable
	cellView = (NSTableCellView *)[super tableView:outlineView viewForTableColumn:tableColumn row:0];
	NSTextField *textField = cellView.textField;
	if(textField) {
		textField.controlSize = NSControlSizeRegular;
		textField.font = [NSFont systemFontOfSize:13.0];	/// the font is a little bigger than in the sample table
	}
	cellView.identifier = ID;
	return cellView;
}


- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
	return NO;  /// the outline view is not meant to select any row.
	
}


- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item {
	return NO;   /// we don't allow collapsing anything.
}


- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item {
	return NO;
}


/// Returns all traces of a given channel among chromatograms of the content array
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
	return traces.copy;
}

#pragma mark - setting contents

- (void)setContentArray:(NSArray *)contentArray {
	/// We don't set the iVar yet because we compare the content with the previous content in `loadContent`
	_needLoadContent = YES;
	[self performSelector:@selector(_loadContent) withObject:nil afterDelay:0];
}



- (void)_loadContent {
	if(!_needLoadContent) {
		return;
	}
	_needLoadContent = NO;
	NSArray *content = MainWindowController.sharedController.sourceController.tableContent.selectedObjects;
	BOOL changeContentType = NO;
	NSInteger contentCount = content.count;
	if(contentCount > 0) {
		BOOL showMarkers = [content.firstObject isKindOfClass: Mmarker.class];
		BOOL showGenotypes = [content.firstObject isKindOfClass: Genotype.class];
		if(showMarkers != self.showMarkers) {
			changeContentType = YES;
			self.showMarkers = showMarkers;
		}
		
		if(showGenotypes != self.showGenotypes) {
			self.showGenotypes = showGenotypes;
		}
		
		if(changeContentType && !showMarkers) {
			[self updateDisplayedChannels]; /// We call this because the NSHiddenBinding of channel buttons with showMarkers somehow enables
											/// the buttons when this property changes (an appkit bug IMO).
		}
	}
	
	if(self.showGenotypes) {
		loadedMarkers = [content uniqueValuesForKeyPath:@"marker"];
		[self configureStackSegmentedControl];
	}
	
	/// we don't immediately load the content if the number of items to show is very large,
	/// which may take some time and block the UI if may row needs to be generated.
	/// The user may have selected the whole source table (of samples or genotypes) for another reason that viewing them
	/// instead, we show a button asking for confirmation
	NSInteger maxItems = self.stackMode == stackModeNone? 400 : INT_MAX;		/// 400 is close to a 384-sample plate
	NSString *itemType = @"Samples";
	if(self.showGenotypes) {
		maxItems = self.stackGenotypes? INT_MAX : 1000;
		itemType = @"Genotypes";
	}
	BOOL buttonShown = _loadContentButton && !_loadContentButton.hidden;
	NSInteger diff = contentCount - _contentArray.count;
	if(contentCount < maxItems || (diff < maxItems && !buttonShown)) {
		if(!buttonShown) {
			[self loadContentArray:content];
		} else {
			_contentArray = content.copy;
			[self reload];
		}
	} else {
		/// We remove all content and show instead the button for user confirmation.
		_contentArray = nil;
		[traceOutlineView reloadData];
		NSButton *loadContentButton = self.loadContentButton;
		loadContentButton.hidden = NO;
		loadContentButton.title = [NSString stringWithFormat:@"Show %ld %@", content.count, itemType];
		_contentArray = content.copy;
	}
}


- (void)setShowGenotypes:(BOOL)showGenotypes {
	_showGenotypes = showGenotypes;
	[self updateChannelButtons];
	[self configureStackSegmentedControl];
	if(showGenotypes) {
		/// if genotypes are shown, the detailed view columns cannot be used for sorting as they do not correspond to those of the genotype table
		/// to avoid confusing the user, we disable sorting.
		[traceOutlineView unbind:NSSortDescriptorsBinding];
		for (NSTableColumn *column in traceOutlineView.tableColumns) {
			if([column.identifier isEqualToString:@"sampleNameColumn"]) {
				/// We change the name of this column to more clearly indicate that the view shows genotypes.
				column.title = @"Genotype of";
			}
			/// We must remove the sort descriptor prototype of each column, otherwise the chevron still appears on the header
			column.sortDescriptorPrototype = nil;
		}
	} else {
		loadedMarkers = nil;
		/// We re-enable sorting when the table no longer show genotypes
		/// (when it shows marker, the header is hidden anyway)
		NSDictionary *columnDescription = self.columnDescription;
		for (NSTableColumn *column in traceOutlineView.tableColumns) {
			if([column.identifier isEqualToString:@"sampleNameColumn"]) {
				column.title = @"Sample";
			}
			column.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:columnDescription[column.identifier][KeyPathToBind] ascending:YES];
		}
		[traceOutlineView bind:NSSortDescriptorsBinding
					  toObject:SampleTableController.sharedController.samples
				   withKeyPath:NSStringFromSelector(@selector(sortDescriptors)) options:nil];
		
	}
}


-(void)configureStackSegmentedControl {
	if(self.showGenotypes) {
		stackSegmentedControl.segmentCount = 2;
		[stackSegmentedControl setToolTip:@"One genotype per row" forSegment:0];
		[stackSegmentedControl setToolTip:@"Stack genotypes by marker" forSegment:1];
		[stackSegmentedControl setImage:[NSImage imageNamed:ACImageNameCallAllelesBadge] forSegment:0];
		[stackSegmentedControl setImage:[NSImage imageNamed:ACImageNameStackGenotypes] forSegment:1];
		[stackSegmentedControl bind:NSSelectedIndexBinding toObject:self withKeyPath:@"stackGenotypes" options:nil];
	} else {
		stackSegmentedControl.segmentCount = 3;
		[stackSegmentedControl setToolTip:@"One trace per row" forSegment:0];
		[stackSegmentedControl setToolTip:@"One sample per row (all colors)" forSegment:1];
		[stackSegmentedControl setToolTip:@"Stack traces by color" forSegment:2];
		[stackSegmentedControl setImage:[NSImage imageNamed:ACImageNameSeparateCurves] forSegment:0];
		[stackSegmentedControl setImage:[NSImage imageNamed:ACImageNameStackChannelsButton] forSegment:1];
		[stackSegmentedControl setImage:[NSImage imageNamed:ACImageNameStackSamples] forSegment:2];
		[stackSegmentedControl bind:NSSelectedIndexBinding toObject:NSUserDefaults.standardUserDefaults withKeyPath:TraceStackMode options:nil];
	}
}


- (void)setStackGenotypes:(BOOL)stackGenotypes {
	_stackGenotypes = stackGenotypes;
	if(self.showGenotypes) {
		if(!_needLoadContent) {
			[self reload];
		}
		[self updateChannelButtons];
	}
}


-(void)loadContentArray:(NSArray *)content {
	_loadContentButton.hidden = YES;
	if(!content ) {
		content = NSArray.new;
	}
	
	/// when the selection of samples/genotypes/markers to show changes, we may react to that by removing and inserting rows instead of just reloading the view
	/// so we compare the new content to the current one
	NSArray *previousContent = self.contentArray;
	
	_contentArray = content.copy;

	/// if we show samples in separate rows or markers (which are always one per row), we do some animation if the new contents contain items that were previously shown
	/// we don't do it if the number of items are too different between the new and previous content.
	int diffCount = abs((int)previousContent.count - (int)content.count);
	BOOL showGenotypes = self.showGenotypes;
	BOOL showMarkers = self. showMarkers;
	BOOL showSamples = !showMarkers && !showGenotypes;
	if (((showSamples && self.stackMode != stackModeSamples) || (showGenotypes && !self.stackGenotypes) || showMarkers) && diffCount <= 10 && diffCount > 0) {
		NSIndexSet *rowsToInsert = [content indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return [previousContent indexOfObjectIdenticalTo:obj] == NSNotFound;  /// gets the index of samples/genotypes that were not shown previously
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
		if (rowsToRemove.count < previousContent.count && [remaining isEquivalentTo:remaining2]) {
			/// we don't animate if the number of rows to show hasn't changed (it would be more disturbing than anything)
			NSInteger animation = content.count == previousContent.count? NSTableViewAnimationEffectNone : NSTableViewAnimationSlideUp;
			
			[traceOutlineView beginUpdates];
			[traceOutlineView removeItemsAtIndexes:rowsToRemove inParent:nil withAnimation:animation];
			/// it's important to remove obsolete rows before inserting new one, and not doing the reverse
			
			if(content.count != previousContent.count) animation = NSTableViewAnimationEffectFade;
			[traceOutlineView insertItemsAtIndexes:rowsToInsert inParent:nil withAnimation:animation];
			[traceOutlineView endUpdates];
			[traceOutlineView expandItem:nil expandChildren:YES];
			[self updateHeader];
			_needLoadContent = NO;
			return;
		}
	}
	[self reload];
}

/// Sent by the loadContent button when the user confirms they want to load the content
-(void)confirmLoadContent:(NSButton *)sender {
	[self reload];
}

/// Updates the header of the outline view as appropriate
-(void) updateHeader {
	/// we hide the header if we don't show individual (non-stacked) samples, as the normal row views (those will columns) are not shown)
	NSInteger itemCount = self.contentArray.count;
	BOOL showGenotypes = self.showGenotypes;
	NSTextField *stackedSampleTextfield = self.stackedSampleTextfield;
	BOOL hideHeader = self.showMarkers || (!showGenotypes && self.stackMode == stackModeSamples && itemCount > 1) || (showGenotypes && self.stackGenotypes);
	traceOutlineView.headerView.hidden = hideHeader;
	stackedSampleTextfield.hidden = !hideHeader || self.showMarkers;
	if(!stackedSampleTextfield.hidden) {
		NSString *stringToShow = @"";
		if(_loadContentButton == nil || _loadContentButton.hidden) {
			if(showGenotypes) {
				if(itemCount < 2) {
					stringToShow = itemCount == 0? @"No genotype selected" : @"1 genotype";
				} else {
					NSInteger markerCount = loadedMarkers.count;
					NSString *s = markerCount > 1? @"s" : @"";
					stringToShow = [NSString stringWithFormat:@"%ld genotypes at %ld marker%@", itemCount, markerCount, s];
				}
			} else {
				stringToShow = [NSString stringWithFormat:@"%ld samples stacked", itemCount];
				if(itemCount > 400 && !showGenotypes) {
					stringToShow = [stringToShow stringByAppendingString:@" (400 shown)"];
				}
			}
		}
		stackedSampleTextfield.stringValue = stringToShow;
	}
}


/// reloads the outline view with new contents
- (void)reload {
	_loadContentButton.hidden = YES;
	if(self.showGenotypes) {
		for(Genotype *genotype in self.contentArray) {
			if([genotype respondsToSelector:@selector(visibleRange)]) {
				genotype.visibleRange = ZeroBaseRange;
			}
		}
		for(Mmarker *marker in loadedMarkers) {
			marker.visibleRange = ZeroBaseRange;
		}
	}
	
	[self updateTraceRowHeight];
	
	[traceOutlineView reloadData];
	[traceOutlineView expandItem:nil expandChildren:YES];
	[self updateHeader];
	_needLoadContent = NO;
}


#pragma mark - adding, removing, resizing rows


- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
	if ([item isKindOfClass: Chromatogram.class] | [item isKindOfClass: Genotype.class] ) {
		///when the element is a chromatogram or genotype, the height of the row showing its metadata is fixed
		return defaultRowHeight;
	}
	return self.traceRowHeight;
}


- (CGFloat)traceRowHeight {
	if(_traceRowHeight < minTraceRowHeight || _traceRowHeight > maxTraceRowHeight) {
		[self updateTraceRowHeight];
	}
	return _traceRowHeight;
}


- (void)setTraceRowHeight:(CGFloat)proposedHeight {
	//// It is important to use a rounded height. Otherwise, some view frames might not start/end at pixel boundaries,
	/// which results in fuzzy rendering and slightly misplaced elements
	/// We avoid making rows taller than the proposed height, to make sure that the bottom row shows in full.
	proposedHeight = floorf(proposedHeight);
	if (proposedHeight < minTraceRowHeight) {
		proposedHeight = minTraceRowHeight;
	} else if(proposedHeight > maxTraceRowHeight) {
		proposedHeight = maxTraceRowHeight;
	}
	_traceRowHeight = proposedHeight;
}


/// Updates the row height given the number of traces the user wants to see and the window height
- (void)updateTraceRowHeight {
	NSUInteger traceRowsPerWindow = MIN(5, MAX(self.numberOfRowsPerWindow, 1));

	float numOtherRows = 0;				/// we compute the number of non-trace rows that should be visible
	BOOL showGenotypes = self.showGenotypes;
	BOOL showMarkers = self.showMarkers;
	BOOL showSamples = !showMarkers && !showGenotypes;
	StackMode stackMode = self.stackMode;
	
	if((showGenotypes && !self.stackGenotypes) || (showSamples && stackMode == stackModeChannels)) {
		numOtherRows = traceRowsPerWindow;
	} else if(showSamples && (stackMode == stackModeNone || self.contentArray.count == 1)) {
		numOtherRows = MIN(traceRowsPerWindow, ceilf((float)traceRowsPerWindow/self.displayedChannels.count));
	}
	
	/// the height is computed such that rows fit the visible height of the table
	/// which is the distance between the header view and the bottom of the clip view (using `visibleRect` on the outline view does not return that)
	NSTableHeaderView *headerView = traceOutlineView.headerView;
	NSClipView *clipView = traceOutlineView.enclosingScrollView.contentView;
	
	NSPoint headerViewBottomLeft = headerView.bounds.origin;
	if(headerView.isFlipped) {
		headerViewBottomLeft.y = NSMaxY(headerView.bounds);
	}
	
	headerViewBottomLeft = [clipView convertPoint:headerViewBottomLeft fromView:headerView];
	CGFloat visibleHeight = NSMaxY(clipView.bounds) - headerViewBottomLeft.y;
	self.traceRowHeight = (visibleHeight - traceOutlineView.intercellSpacing.height*(traceRowsPerWindow + numOtherRows) - numOtherRows*defaultRowHeight) / traceRowsPerWindow;
}



- (void)setNumberOfRowsPerWindow:(NSUInteger)numberOfRowsPerWindow {
	_numberOfRowsPerWindow = MIN(5, MAX(1, numberOfRowsPerWindow));
	if(traceOutlineView.numberOfRows > 0) {
		[self resizeRows:self];
	}
}


- (void)viewDidLayout {
	[super viewDidLayout];
	if(self.view.inLiveResize) {
		/// We resize rows so that the number of visible rows adjusts to the visible height of the the detailed view.
		[self resizeRows:nil];
	}
}

///resizes the rows showing traces when the users adjusts the slider (sender) or resizes the view (sender = nil in this case)
- (IBAction)resizeRows:(id)sender {
	CGFloat currentHeight = self.traceRowHeight;
	[self updateTraceRowHeight];
	if(currentHeight == self.traceRowHeight) {
		/// when the window is resized only horizontally, the row height should not change, and it is better to return.
		/// If we don't, the pointless animation interferes with the resizing of trace views
		return;
	}
	/// This method also scrolls the table so that the position of the topmost visible row edge doesn't change
	/// If we didn't scroll, the change in row height would result in traces moving down as they get taller, or up as they get shorter, which would be disturbing, especially during window resizing.
	/// to achieve this, we count the number of traceRow above the visible rectangle
	/// we compute the difference in height due to resizing of the trace views
	
	NSRect clipViewBounds = traceOutlineView.enclosingScrollView.contentView.bounds;
	NSUInteger rowCount = traceOutlineView.numberOfRows;
	float traceRowsAbove = 0;
	for (NSInteger row = 0; row < rowCount; row++) {
		NSRect frame = [traceOutlineView rectOfRow:row];
		if(frame.origin.y >= clipViewBounds.origin.y) {
			break;
		}
		if(frame.size.height >= minTraceRowHeight -1) {
			traceRowsAbove ++;
		}
	}
	
	CGFloat traceRowHeightAbove = traceRowsAbove * currentHeight;						/// the total height they represent
	CGFloat heightDiff = traceRowsAbove  * self.traceRowHeight - traceRowHeightAbove;		/// and the difference in height after they are resized
	
	[traceOutlineView beginUpdates];
	NSAnimationContext *context = NSAnimationContext.currentContext;
	if(sender == nil) {
		context.duration = 0.0;					/// we don't animate during live resize
		context.allowsImplicitAnimation = NO;
	}
	
	[traceOutlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,rowCount)]];
	
	if(heightDiff != 0) {
		/// we scroll the view by modifying its clipview's bounds origin (which is animatable)
		NSPoint origin = clipViewBounds.origin;
		origin.y += heightDiff;		/// this will be the new origin
		
		[NSAnimationContext beginGrouping];
		/// we scroll synchronously with the row height animation. The grouping prevents certain rows from flying around
		/// we don't use the animator proxy, as it results in jerky scrolling.
		context.allowsImplicitAnimation = sender != nil;  	/// we don't animate the scroll during window resizing.
		/// scrollToPoint: forces the scrolling to the destination even if the outline view doesn't have its final size (scrollPoint: or setBoundsOrigins: can't do that).
		[(NSClipView *)traceOutlineView.superview scrollToPoint:origin];
		[NSAnimationContext endGrouping];
	}
	[traceOutlineView endUpdates];
	
}



/// Reveals or hides rows showing particular channels.
/// To work properly, this method must not be called within a `beingUpdates/endUpdates` block.
- (void)hideChannels:(NSIndexSet*)rowsToRemove showChannels:(NSIndexSet*) rowsToInsert {
	NSInteger contentCount = self.contentArray.count;
	if (self.showGenotypes || self.showMarkers || contentCount == 0) {
		/// this is a safety measure, as this method should not be called in these situations
		return;
	}
	
	/// Inserting/removing rows in each sample (parent) causes performance and tiling issues when there are many parents.
	/// We instead reload the whole table, which is the only method that is fast when there are hundreds of samples (`reloadItem:` is too slow).
	/// Then we insert/remove rows with animation for parents that are in the visible rectangle. This provides visual feedback about what happened.
	
	BOOL stacksSamples = self.stackMode == stackModeSamples && contentCount > 1;
	/// We determine the parents for which we will remove/insert rows.
	NSArray *parents = stacksSamples? @[NSNull.null] : self.contentArray; /// NSNull will be interpreted as nil (the root parent)
	NSInteger insertedCount = rowsToInsert.count, removedCount = rowsToRemove.count;

	if(!stacksSamples) {
		/// As the height of the outline view will change, the samples that are visible may move down/up, which would confuse users
		/// We scroll to maintain the position of the first sample (parent) whose affected rows are visible.
		NSRect visibleRect = traceOutlineView.visibleRectBelowHeader;
		NSInteger firstVisibleRow = MAX(0, [traceOutlineView rowAtPoint:visibleRect.origin]);
		NSInteger rowCountPerParent = traceOutlineView.numberOfRows/contentCount;
		NSInteger firstVisibleParent = firstVisibleRow / rowCountPerParent;
	
		/// Under certain conditions, we take as reference the first sample whose parent row is visible (for best visual feedback).
		/// This is the next sample in the table.
		NSInteger firstVisibleChildRowChildIndex = firstVisibleRow - firstVisibleParent*rowCountPerParent-1;
		NSInteger lastRowForFirstVisibleParent = (firstVisibleParent+1)*rowCountPerParent -1;
		CGFloat firstParentVisibleHeight = NSMaxY([traceOutlineView rectOfRow:lastRowForFirstVisibleParent]) - visibleRect.origin.y;
		NSInteger lastIndex1 = insertedCount > 0 ? rowsToInsert.lastIndex : -1;
		NSInteger lastIndex2 = removedCount > 0 ? rowsToRemove.lastIndex : -1;
		NSInteger lastAffectedChild = MAX(lastIndex1-1, lastIndex2);
		firstVisibleParent += (lastAffectedChild < firstVisibleChildRowChildIndex || (firstParentVisibleHeight < 0.5*self.traceRowHeight));

		[self updateTraceRowHeight];
		
		/// We record the position of the first visible parent row to compare it after the change
		NSInteger parentRow = firstVisibleParent*(rowCountPerParent);
		CGFloat parentRowTop = [traceOutlineView rectOfRow:parentRow].origin.y;
		NSPoint origin = traceOutlineView.scrollPoint;

		[traceOutlineView reloadData];
		
		rowCountPerParent = traceOutlineView.numberOfRows/contentCount;
		parentRow = firstVisibleParent*(rowCountPerParent);
		/// An alternative would be to predict the difference based on the row heights and numbers, but sometime the actual position
		/// does not conform predictions (tiling issues I suppose).
		CGFloat diff = [traceOutlineView rectOfRow:parentRow].origin.y - parentRowTop;
		
		if(diff != 0) {
			[traceOutlineView scrollPoint:NSMakePoint(origin.x, origin.y + diff)];
		}
		
		/// We now insert/remove rows with animation for visible parents. We identify these parents.
		NSInteger lastVisibleParent = [traceOutlineView rowAtPoint:traceOutlineView.bottomLeftPoint]/rowCountPerParent;
		if(lastVisibleParent < firstVisibleParent) {
			parents = nil;
		} else {
			parents = [parents objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(firstVisibleParent, lastVisibleParent - firstVisibleParent+1)]];
			
			/// As the reload has inserted/removed the rows that we wanted removed/inserted with animation,
			/// we undo that by removing/inserted rows in the visible parents using the previous settings.
			/// The alternative would have been to reload all parent except these ones, but it is too slow when there are many.
			NSArray *currentDisplayedChannels = _displayedChannels.copy; /// We record the current settings
			StackMode currentStackMode = _stackMode;
			
			[traceOutlineView beginUpdates];
			if(insertedCount > 0) {
				for(id parent in parents) {
					[traceOutlineView removeItemsAtIndexes:rowsToInsert inParent:parent withAnimation:NSTableViewAnimationEffectNone];
				}
			}
			
			if(removedCount > 0) {
				_stackMode = previousStackMode;
				_displayedChannels = previousDisplayedChannels;
				for(id parent in parents) {
					[traceOutlineView insertItemsAtIndexes:rowsToRemove inParent:parent withAnimation:NSTableViewAnimationEffectNone];
				}
			}
			[traceOutlineView endUpdates];
			
			if(rowsToRemove.count > 0) {
				/// We restore the current settings, which must be done after `endUpdates`.
				_displayedChannels = currentDisplayedChannels;
				_stackMode = currentStackMode;
			}
		}
	}
	
	/// We now insert/remove rows with animation.
	[traceOutlineView beginUpdates];
	if(removedCount > 0) {
		for(id parent in parents) {
			[traceOutlineView removeItemsAtIndexes:rowsToRemove inParent:parent==NSNull.null? nil:parent withAnimation:NSTableViewAnimationSlideUp];
		}
	}
	
	if(insertedCount > 0) {
		for(id parent in parents) {
			[traceOutlineView insertItemsAtIndexes:rowsToInsert inParent:parent==NSNull.null? nil:parent withAnimation:NSTableViewAnimationSlideDown];
		}
	}
	[traceOutlineView endUpdates];
}



- (void)setStackMode:(StackMode)stackMode {
	if(self.stackMode != stackMode) {
		previousStackMode = _stackMode;
		_stackMode = stackMode;
		if(!self.showGenotypes && !self.showMarkers) { /// A safety measure as the controls to change stack mode are not enabled in this case
			NSInteger contentCount = self.contentArray.count;
			
			/// We determine of to reflect the change in the detailed view.
			BOOL channelStackChange = stackMode == stackModeChannels || previousStackMode == stackModeChannels & contentCount > 0;
			BOOL channelStackVisualChange = self.displayedChannels.count > 1 && channelStackChange;
			BOOL sampleStackVisualChange = contentCount > 1 && (stackMode == stackModeSamples || previousStackMode == stackModeSamples);
			if(sampleStackVisualChange || (channelStackChange && !channelStackVisualChange)) {
				/// If only the second condition is true (i.e., one channel shown), the change is invisible to the user, but we reload
				/// as trace views must load traces for all channels (even if they show only one) when the mode is stackModeChannels
				/// or load only one trace in other mods.
				[self reload];
			} else if(channelStackVisualChange) {
				/// We animate the change by removing or revealing rows for separate channels, except the first row of each sample.
				/// This row will be reloaded in `hideChannels:showChannels`.
				NSIndexSet *rowsForSeparateChannels = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, self.displayedChannels.count-1)];
				if (stackMode == stackModeChannels) {
					[self hideChannels:rowsForSeparateChannels showChannels:NSIndexSet.new];
				} else {
					[self hideChannels:NSIndexSet.new showChannels:rowsForSeparateChannels];
				}
			}
		}
		previousStackMode = stackMode;
	}
}


#pragma mark - management of colors to show


- (NSArray <NSNumber *> *)displayedChannels {
	if(!_displayedChannels) {
		[self updateDisplayedChannels];
	}
	return _displayedChannels;
}


- (void)updateChannelButtons {
	NSArray *channelPrefKeys = _showGenotypes? channelPreferenceKeysG : channelPreferenceKeys;
	NSString *toolTip = _showGenotypes? @"Show this channel for all markers" : @"Option-click to show only this channel";
	NSUserDefaults *standardUserDefaults = NSUserDefaults.standardUserDefaults;
	for(NSButton *channelButton in channelButtons) {
		channelButton.toolTip = toolTip;
		[channelButton bind:NSValueBinding toObject:standardUserDefaults withKeyPath:channelPrefKeys[channelButton.tag] options:nil];
	}
	[self updateDisplayedChannels];
}


- (void)updateDisplayedChannels {
	NSInteger nChannels = 5;
	NSMutableArray *newDisplayedChannels = [NSMutableArray arrayWithCapacity:nChannels];  /// we update the channels to display
	NSArray *channelPrefKeys = self.showGenotypes? channelPreferenceKeysG : channelPreferenceKeys;
	for (int channel = 0; channel < nChannels; channel++) {
		if ([NSUserDefaults.standardUserDefaults boolForKey:channelPrefKeys[channel]]) {
			[newDisplayedChannels addObject:@(channel)];
		}
	}
	
	if(newDisplayedChannels.count == 0 && !self.showGenotypes) {
		/// We impose that at least one channel is shown.
		[NSUserDefaults.standardUserDefaults setBool:YES forKey:ShowChannel0];
		[newDisplayedChannels addObject:@0];
	}
	
	self.displayedChannels = newDisplayedChannels;
	BOOL disableButtons = self.stackGenotypes && self.showGenotypes;
	for (NSButton *button in channelButtons) {
		button.enabled = !disableButtons && (self.showGenotypes || !(button.state == NSControlStateValueOn && newDisplayedChannels.count == 1));
	}
}


/// Message sent by buttons that show/hide channels.
- (IBAction)toggleChannelVisibility:(NSButton*)sender {
	BOOL altKeyDown = (NSApp.currentEvent.modifierFlags & NSEventModifierFlagOption) != 0;
	///if alt key is pressed, we only show the channel associated with the button, regardless of its previous state
	if (altKeyDown) {
		NSArray *channelPrefKeys = self.showGenotypes? channelPreferenceKeysG : channelPreferenceKeys;
		for (int channel = 0; channel <= 4; channel++) {
			[NSUserDefaults.standardUserDefaults setBool:NO forKey:channelPrefKeys[channel]]; /// we first deselect all channels
		}
		[NSUserDefaults.standardUserDefaults setBool:YES forKey:channelPrefKeys[sender.tag]]; ///and enable the channel corresponding to the button tag
	}
	
	previousDisplayedChannels = self.displayedChannels;
	[self updateDisplayedChannels];
	NSArray<NSNumber *> *currentDisplayChannels = self.displayedChannels;
	
	if(self.stackMode != stackModeChannels && self.contentArray.count > 0 && !self.showMarkers && !self.showGenotypes) {
		/// Here, channels are shown in separate rows. We must reload the table or remove/insert rows to reflect the change.
		/// We check that the number of trace rows per parent corresponds to the number of channels shown.
		/// If not (which would be a bug), we reload the table.
		BOOL stackSamples = self.stackMode == stackModeSamples && _contentArray.count > 1;
		NSInteger childRowCounts = traceOutlineView.numberOfRows / (stackSamples? 1:_contentArray.count) - !stackSamples;
		if(childRowCounts != previousDisplayedChannels.count) {
			NSLog(@"Error: number of child rows (%ld) differs from displayed channels (%ld)!", childRowCounts, previousDisplayedChannels.count);
			[traceOutlineView reloadData];
			return;
		}
		
		if(previousDisplayedChannels.count == currentDisplayChannels.count) {
			/// if the number of visible channels did not change we just reload the outline view
			/// (inserting rows and removing rows at the same time, with animation, would be costly and visually disturbing)
			[traceOutlineView reloadData];
			return;
		}
		/// else we reveal/hide rows with animation.
		/// We get the index of channels that should be hidden.
		NSIndexSet *rowsToRemove = [previousDisplayedChannels indexesOfObjectsPassingTest:^BOOL(NSNumber *channel, NSUInteger idx, BOOL *stop) {
			return ![currentDisplayChannels containsObject:channel];
		}];
				
		NSIndexSet *rowsToInsert = nil;
		if(rowsToRemove.count == 0 || stackSamples) {
			/// When traces are not stacked, we insert rows only if none is removed..
			/// Inserting rows while removing others (which may happen if the used has pressed the alt key) is visually disturbing.
			/// The `hideChannel:showChannels:` methods reloads the table, so any new channel will show anyway.
			rowsToInsert = [currentDisplayChannels indexesOfObjectsPassingTest:^BOOL(NSNumber *channel, NSUInteger idx, BOOL *stop) {
				return ![previousDisplayedChannels containsObject:channel];
			}];
		}
		
		[self hideChannels:rowsToRemove showChannels:rowsToInsert];
	}
	previousDisplayedChannels = currentDisplayChannels;
}



#pragma mark - column management

- (BOOL)canHideColumn:(NSTableColumn *)column {
	return ![column.identifier isEqualToString:@"sampleNameColumn"];
}


- (BOOL)outlineView:(NSOutlineView *)outlineView shouldReorderColumn:(NSInteger)columnIndex toColumn:(NSInteger)newColumnIndex {
	NSTableColumn *columnToMove = outlineView.tableColumns[columnIndex];
	
	if([columnToMove.identifier isEqualToString:@"sampleNameColumn"] && newColumnIndex > 0) {
		return NO;
	}
	
	if(![columnToMove.identifier isEqualToString:@"sampleNameColumn"] && newColumnIndex == 0) {
		return NO;
	}
	
	return YES;
}


- (CGFloat)outlineView:(NSOutlineView *)outlineView sizeToFitWidthOfColumn:(NSInteger)column {
	return [super tableView:outlineView sizeToFitWidthOfColumn:column];
}


#pragma mark - delegate methods for traceTableView

- (BOOL)canSelectItemsForOutlineView:(NSOutlineView *)traceOutlineView {
	return [MainWindowController.sharedController.sourceController.tableContent.arrangedObjects count] > 0;
}


- (void)selectAll:(id)sender {
	[MainWindowController.sharedController.sourceController.tableView selectAll:sender];
}


- (void)deselectAll:(id)sender {
	[MainWindowController.sharedController.sourceController.tableView deselectAll:sender];
}


- (void)outlineView:(NSOutlineView *)outlineView keyDown:(NSEvent *)event {
	[MainWindowController.sharedController.sourceController.tableView keyDown:event];
}




#pragma mark - delegate methods for traceViews

/// Reveals the item (sample or genotype) represented by the row of the sender in its source table.
-(void)revealInList:(NSButton *)sender {
	id itemToReveal;
	NSTableCellView *cellView = (NSTableCellView *)sender.superview;
	if(![cellView isKindOfClass:NSTableCellView.class]) {
		return;
	}
	
	if(self.showGenotypes) {
		/// In this case, the genotype to reveal is not represented by the row of the sender (it is the genotype's sample).
		/// The genotype is represented at the next row.
		NSInteger row = [traceOutlineView rowForView:cellView];
		id nextItem = [traceOutlineView itemAtRow:row+1];
		if([nextItem isKindOfClass:NSSet.class]) {
			itemToReveal = [nextItem anyObject];
		}
	} else {
		itemToReveal = cellView.objectValue;
	}
	
	if(itemToReveal) {
		[self traceView:nil revealSourceItem:itemToReveal isolate:NO];
	}
}


-(void) traceView:(TraceView *)traceView revealSourceItem:(id)itemToReveal isolate:(BOOL)isolate {
	if(!itemToReveal) {
		return;
	}
	
	if([itemToReveal isKindOfClass:Trace.class]) {
		itemToReveal = [itemToReveal chromatogram];
	} else if([itemToReveal isKindOfClass:Allele.class]) {
		itemToReveal = [itemToReveal genotype];
	} else if([itemToReveal isKindOfClass:LadderFragment.class]) {
		itemToReveal = [[itemToReveal trace] chromatogram];
	}
		
	MainWindowController *mainWindowController = MainWindowController.sharedController;
	TableViewController *controller = mainWindowController.sourceController;
	mainWindowController.sourceController = controller; /// this makes sure that the genotype list is shown if needed
	if(isolate) {
		if([controller.tableContent setSelectedObjects:@[itemToReveal]]) {
			if([itemToReveal isKindOfClass:Genotype.class]) {
				self.stackGenotypes = NO;
			}
		}
	} else {
		[controller flashItem:itemToReveal];
	}
}


- (void)recordReferenceRange {
	[NSUserDefaults.standardUserDefaults setFloat:referenceRange.start forKey:ReferenceStartSize];
	[NSUserDefaults.standardUserDefaults setFloat:referenceRange.start + referenceRange.len forKey:ReferenceEndSize];
}


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



- (NSMenu *)menuForSizeStandardsForView:(TraceView *)view withFontSize:(CGFloat)fontSize{
	NSMenu *menu = NSMenu.new;
	menu.font = [NSFont systemFontOfSize:fontSize];
	for(SizeStandard *standard in SizeStandardTableController.sharedController.tableContent.arrangedObjects) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:standard.name action:@selector(applySizeStandard:) keyEquivalent:@""];
		item.target = self;
		item.representedObject = standard;
		[menu addItem:item];
	}
	traceViewForMenu = view;
	return menu;
}


- (NSMenu *)menuFoPanelsForView:(TraceView *)view withFontSize:(CGFloat)fontSize {
	traceViewForMenu = view;
	return [PanelListController.sharedController menuForPanelsWithTarget:self fontSize:fontSize];
}


-(void)applySizeStandard:(NSMenuItem *)sender {
	SizeStandard *standard = sender.representedObject;
	if(standard) {
		TraceView *traceView = traceViewForMenu;
		if([traceView respondsToSelector:@selector(loadedTraces)]) {
			NSArray *samples = [traceView.loadedTraces valueForKeyPath:@"@distinctUnionOfObjects.chromatogram"];
			if(samples.count > 0) {
                if(samples.count > 1 && self.stackMode == stackModeSamples && samples.count < _contentArray.count) {
                    samples = self.contentArray;
                }
				[SizeStandardTableController.sharedController applySizeStandard:standard toSamples:samples];
			}
		}
	}
}


-(void)applyPanel:(NSMenuItem *)sender {
	Panel *panel = sender.representedObject;
	if(panel && traceViewForMenu) {
		if([traceViewForMenu respondsToSelector:@selector(loadedTraces)]) {
			NSArray *samples = [traceViewForMenu.loadedTraces valueForKeyPath:@"@distinctUnionOfObjects.chromatogram"];
			if(samples.count > 0) {
				if(samples.count > 1 && self.stackMode == stackModeSamples && samples.count < _contentArray.count) {
					samples = self.contentArray;
				}
				[PanelListController.sharedController applyPanel:panel toSamples:samples];
			}
		}
	}
}

# pragma mark - other user actions

- (NSArray *)validTargetsOfSender:(id)sender {
	if([sender respondsToSelector:@selector(action)] && [sender action] == @selector(copy:)) {
		return nil; /// We do no copy items shown in the outline view. 
	}
	return self.contentArray;
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(menuItem.action == @selector(moveSelectionByStep:)) {
		return [MainWindowController.sharedController.sourceController validateMenuItem:menuItem];
	}
	return [super validateMenuItem:menuItem];
}


- (void)moveSelectionByStep:(id)sender {
	[MainWindowController.sharedController.sourceController moveSelectionByStep:sender];
}


# pragma mark - printing

-(IBAction)print:(id)sender {
	NSInteger rowCount = traceOutlineView.numberOfRows;
	if(rowCount <= 0) {
		/// The print menu should be disabled in this situation, this is a safety measure.
		NSError *error = [NSError errorWithDescription:@"There is nothing to print" suggestion:@""];
		[[NSAlert alertWithError:error] runModal];
		return;
	}

	NSPrintInfo *printInfo = NSPrintInfo.sharedPrintInfo.copy;
	
	printInfo.leftMargin = 20;
	printInfo.rightMargin = 20;
	printInfo.topMargin = 20;
	printInfo.bottomMargin = 20;
	printInfo.horizontalPagination = NSPrintingPaginationModeFit;
	printInfo.horizontallyCentered = NO;
	printInfo.verticallyCentered = NO;
		
	/// We don't print the trace outline view itself, as it does not print in a nice and performant fashion.
	/// (overriding public printing methods in TraceOutlineView is not an option, as appkit uses private methods for printing table views).
	TraceOutlineViewPrinter *printedView = [[TraceOutlineViewPrinter alloc] initWithView:traceOutlineView];
	CGFloat printableWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin;
	CGFloat contentWidth = printedView.bounds.size.width;
	
	/// Setting the scale factor to fit the view horizontally
	printInfo.scalingFactor =  printableWidth / contentWidth;
	
	NSPrintOperation *printOperation = [NSPrintOperation printOperationWithView:printedView printInfo:printInfo];
	NSPrintPanel *panel = printOperation.printPanel;
	
	panel.options = NSPrintPanelShowsCopies |
	NSPrintPanelShowsPageRange |
	NSPrintPanelShowsPaperSize |
	NSPrintPanelShowsPreview |
	NSPrintPanelShowsScaling |
	NSPrintPanelShowsOrientation;
	
	printOperation.showsPrintPanel = YES;
	printOperation.showsProgressPanel = YES;
	
	[printOperation runOperation];
	printedTraceRowView = nil;
	printedStandardRowView = nil;
	printedNoTraceRowView = nil;
}



- (NSTableRowView *)outlineView:(TraceOutlineView *)outlineView printableRowViewForItem:(id)item clipToVisibleWidth:(BOOL)clipped {
	NSTableRowView *rowView;
	CGFloat width = clipped? outlineView.visibleRect.size.width : outlineView.frame.size.width;
	NSSize size = NSMakeSize(width, self.traceRowHeight);
	if(item == NSNull.null || ([item isKindOfClass:NSArray.class] && [item count] == 0)) {
		if(!printedNoTraceRowView) {
			printedNoTraceRowView = [outlineView makeViewWithIdentifier:@"noTraceRowViewKey" owner:self];
			NSTextField *textField = printedNoTraceRowView.subviews.firstObject;
			[textField setTranslatesAutoresizingMaskIntoConstraints:YES];
		}
		rowView = printedNoTraceRowView;
	} else if([item isKindOfClass: Chromatogram.class] || [item isKindOfClass:Genotype.class]) {
		size.height = defaultRowHeight;
		rowView = printedStandardRowView;
		if(!rowView) {
			rowView = [[NSTableRowView alloc] initWithFrame: NSMakeRect(0, 0, size.width, size.height)];
			printedStandardRowView = rowView;
			/// We add the table cell views corresponding to columns
			CGFloat currentX =  1 + (clipped? -outlineView.visibleRect.origin.x : 0); /// The X position of the last table cell view added to the row view.
			CGFloat spacing = traceOutlineView.intercellSpacing.width;
			for(NSTableColumn *column in self.visibleColumns) {
				if(currentX + column.width >= 0) {
					NSView *cellView = [self outlineView:outlineView viewForTableColumn:column item:item];
					if(cellView) {
						cellView.frame = NSMakeRect(currentX, 0, column.width, size.height);
						[rowView addSubview:cellView];
					}
				}
				currentX += column.width + spacing;
				if(currentX > size.width) {
					break;
				}
			}
			[self configureViewForPrinting:rowView];
		}
		/// We set the content of the table cell views given the item
		for(NSTableCellView *cellView in rowView.subviews) {
			/// We don't care about column, as the object represented by the row is the same for all column
			/// This is not flexible, but unlikely to change in the future.
			cellView.objectValue = [self outlineView:outlineView objectValueForTableColumn:nil byItem:item];
		}
	} else {
		rowView = [self outlineView:outlineView traceRowViewForItem:item printing:YES];
	}
		
	if(!NSEqualSizes(rowView.frame.size, size)) {
		[rowView setFrameSize:size];
	}
	
	return rowView;
}


/// Makes a view's subviews adequate for printing by using white backgrounds when possible and hiding buttons
-(void) configureViewForPrinting:(NSView *)view {
	NSArray *subViews = [[self.class allSubviewsOf:view] arrayByAddingObject:view];
	for(NSButton *subView in subViews) {
		/// We make the subview as white as possible.
		subView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
		if ([subView respondsToSelector:@selector(setBackgroundColor:)]) {
			NSColor *backgroundColor;
			if ([subView respondsToSelector:@selector(backgroundColor)] && [subView respondsToSelector:@selector(setBackgroundColor:)]) {
				backgroundColor = [subView performSelector:@selector(backgroundColor)];
			}
			if (backgroundColor && ![backgroundColor isEqual:NSColor.clearColor]) {
				[subView performSelector:@selector(setBackgroundColor:) withObject:NSColor.whiteColor];
			}
		}

		if([subView isKindOfClass:NSButton.class]) {
			subView.hidden = YES; /// We don't print buttons.
		} else if([subView isKindOfClass:LabelView.class]) {
			subView.wantsLayer = NO; /// So these views will use drawRect when printed.
		}
	}
}


/// Returns all subviews of a view, recursively.
/// - Parameter view: a view.
+ (NSArray *)allSubviewsOf:(NSView *)view {
	/// We could have made this a category of `NSView`, but this method is only used here.
	NSMutableArray *allSubviews = [NSMutableArray arrayWithObject:view];
	NSArray *subviews = view.subviews;
	for (NSView *view in subviews) {
		[allSubviews addObjectsFromArray:[self allSubviewsOf:view]];
	}
	return allSubviews.copy;
}


@end

