//
//  TraceView.m
//  STRyper
//
//  Created by Jean Peccoud on 27/08/12.
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



#import "TraceView.h"

#import "FragmentLabel.h"
#import "TraceScrollView.h"
#import "VScaleView.h"
#import "Mmarker.h"
#import "Panel.h"
#import "Bin.h"
#import "PeakLabel.h"
#import "MarkerView.h"
#import "RulerView.h"
#import "Genotype.h"
#import "LadderFragment.h"

@interface TraceView ()

/// redefinition of properties that are readonly by other objects
@property (nonatomic) ChannelNumber channel;
@property (nonatomic, nullable) NSArray *binLabels;
@property (nonatomic, nullable) NSArray *peakLabels;
@property (nonatomic, nullable) NSArray *fragmentLabels;
@property (nonatomic) BOOL isResizing;
@property (nonatomic) RulerView *rulerView;

/// the label of marker whose bins are being edited. This can be set by the marker itself, but it should not be set arbitrarily
@property (nonatomic, weak) RegionLabel *enabledMarkerLabel;
																		
/// Used to animate a change in visibleRange. We use NSSize rather than BaseRange because the animator doesn't recognize the BaseRange struct.
@property (nonatomic) NSSize animatableRange;

/// Colors used to drawn offscale regions depending in the channel that presumably saturated the camera. These colors are derived from colorsForChannels
@property (nonatomic) NSArray<NSColor *> *colorForOffScaleScans;

/// Property that can be bound to the NSApp effective appearance. There is no ivar backing it it, the setter just tells the view to conform to the app's appearance.
@property (nonatomic) NSAppearance *viewAppearance;

@end

/// pointers giving context to KVO notifications
static void * const displaySettingsChangedContext = (void*)&displaySettingsChangedContext;
static void * const sampleSizingChangedContext = (void*)&sampleSizingChangedContext;
static void * const panelChangedContext = (void*)&panelChangedContext;
static void * const endSizeChangedContext = (void*)&endSizeChangedContext;
static void * const peakChangedContext = (void*)&peakChangedContext;
static void * const fragmentsChangedContext = (void*)&fragmentsChangedContext;

/// we give values to the binding names
NSBindingName const ShowOffScaleRegionsBinding = @"showOffscaleRegions",
ShowPeakTooltipsBinding = @"showPeakTooltips",
ShowBinsBinding = @"showDisabledBins",
ShowRawDataBinding = @"showRawData",
MaintainPeakHeightsBinding = @"maintainPeakHeights",
AutoScaleToHighestPeakBinding = @"autoScaleToHighestPeak",
DisplayedChannelsBinding = @"displayedChannels",
IgnoreCrossTalkPeaksBinding = @"ignoreCrosstalkPeaks",
DefaultRangeBinding = @"defaultRange";

/// some variables shared by all instances
static NSArray *animatableKeys;

static const float maxHScale = 500.0; 	/// the maximum hScale (pts per base pair), to avoid making the view too wide.

NSDictionary *gLabelFontStyle;      /// font used for various labels, used by viewLabels and the ruler view
static const int threshold = 1;   	/// height (in points) below which we do not add points to the fluorescence curve and just draw a straight line (optimization)

static NSMenu *addPeakMenu;			/// a menu that allows adding a peak that hasn't been automatically detected (mostly because it's too faint)


@implementation TraceView {
	
	float height;					/// a shortcut to the view's height (not used often. Could be removed)
	BOOL isDragging;               	/// the views must know whether the some mouse buttons are being pressed, which we use to drag or resize the view (not currently used)
	float maxReadLength;			/// the length (in base pairs) of the longest trace the view shows
	float viewLength;				/// It is either the maxReadLength or the max end size the user as set in the preferences, whichever is longer
	__weak MarkerView *_markerView;	/// the view showing the markers, which is the accessory view of the ruler view
	NSTimer *resizingTimer;
	CAShapeLayer *dashedLineLayer;	/// a layer showing a vertical dashed line at the mouse location that helps the user insert bins (note: we could use a single instance in a global variable for this layer, since only one dashed line should show at a time)
	NSBezierPath *curve;			/// the bezier path we use to draw the traces
	
	float startPoint; 						/// (for dragging... not used)
	
	NSArray<Trace *> *visibleTraces;		/// the traces that are actually visible, depending on the channel to show
	
	NSArray *observedSamples;			/// The chromatograms we observe for certain keypaths.
	NSArray *observedSamplesForPanel;
	
	__weak RegionLabel *hoveredBinLabel;	/// the bin label being hovered, which we use to determine the cursor
	BOOL showMarkerOnly;
	
}


/// Notes on drawing:
/// Traces are drawn in drawRect: on the backing layer. This allows drawing only what's visible (important for smoothness during zoom) and discarding what's hidden to save memory.
/// Appkit does this automatically, taking advantage of core animation during scrolling to avoid redrawing at every step.
///
/// Reproducing appkit's implementation on a custom layer would be quite complex. The view can be very wide (tens of thousands of points), and appkit complains if we create a CALayer this large (while it has no issue with a very wide backing layer).
/// It has no issue with a large CATiledLayer, but tiles drawn in separate threads produces artefacts as the current hScale and  vScale may not correspond to the value used for a tile being displayed. CATiledLayer is designed for large fixed images and not for what we do.
///
/// Because the traces draw on the backing layer, this layer is not opaque since labels that show behind traces (namely, binLabels should be visible.
/// These labels use CALayers that are hosted by the superview (the clipview).
/// This works very well as these layers automatically move in sync with the document view

@synthesize markerLabels = _markerLabels, backgroundLayer = _backgroundLayer;

#pragma mark - initialization methods

+ (void)initialize {
	
	gLabelFontStyle = @{NSFontAttributeName: [NSFont labelFontOfSize:8.0], NSForegroundColorAttributeName: NSColor.secondaryLabelColor};
	
	animatableKeys = @[NSStringFromSelector(@selector(topFluoLevel)),
					   NSStringFromSelector(@selector(animatableRange)),
					   NSStringFromSelector(@selector(vScale))];
	
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if(self) {
		[self setAttributes];
	}
	return self;
}


- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if(self) {
		[self setAttributes];
	}
	return self;
}


-(void)setAttributes {
	[NSUserDefaults.standardUserDefaults addObserver:self forKeyPath:OutlinePeaks options:NSKeyValueObservingOptionNew context:displaySettingsChangedContext]; /// TO REMOVE when shipping
	
	self.layer.drawsAsynchronously = YES;  			/// this seems to improve performance in general, and offloads the drawing to the GPU on Apple Silicon
	self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
	
	/************************attributes related to visuals*******/
	/// we initialize the layer showing the dashed line that show at the mouse location over the enabled marker label
	dashedLineLayer = CAShapeLayer.new;
	dashedLineLayer.anchorPoint = CGPointMake(1, 0); /// this will position the layer at the left of the mouse location, which place it more in line with the cursor
	dashedLineLayer.fillColor = NSColor.clearColor.CGColor;
	dashedLineLayer.strokeColor = NSColor.darkGrayColor.CGColor;
	dashedLineLayer.lineWidth = 1.0;
	dashedLineLayer.lineDashPattern = @[@(1.0), @(2.0)];
	dashedLineLayer.actions = @{NSStringFromSelector(@selector(position)): NSNull.null,
								NSStringFromSelector(@selector(bounds)): NSNull.null};
	[self.layer addSublayer:dashedLineLayer];
	
	curve = NSBezierPath.new;
	curve.lineWidth = 1.0;
	
	_showDisabledBins = YES;
	_showRawData = NO;
	_showOffscaleRegions = YES;
	_verticalOffset = 1.0;
	_defaultRange = MakeBaseRange(0, 500);
	_hScale = -1.0;  /// we avoid 0 as some methods divide numbers by this ivar
	
	/************************observations to update view labels **************/
	/// peak and fragment labels must be updated when peaks and fragments of the trace we show change.
	[self addObserver:self forKeyPath:@"trace.peaks" options:NSKeyValueObservingOptionNew context:peakChangedContext];
	[self addObserver:self forKeyPath:@"trace.fragments" options:NSKeyValueObservingOptionNew context:fragmentsChangedContext];
	
	/// For marker and bin labels, we use the notification center. This is easier than observing each loaded marker for its bin property
	/// We don't specify a panel or marker as the notifying object, as we can show any panel or marker.
	/// There won't be many markers or panel sending notifications at a given time.
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(markerBinsDidChange:) name:MarkerBinsDidChangeNotification object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(panelMarkersDidChange:) name:PanelMarkersDidChangeNotification object:nil]; /// for the panel's marker, we could have observed our panels.markers keyPath, which may work just a well
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(genotypeOffsetDidChange:) name:GenotypeDidChangeOffsetCoefsNotification object:nil];
	
}


- (CALayer *)backgroundLayer {
	if(!_backgroundLayer) {
		self.superview.wantsLayer = YES;
		if(!self.superview.layer) {
			return nil;
		}
		/// since our bounds origin may change, can cannot just return the clipview's backing layer.
		/// The clipview's backing layer geometry should not be changed.
		_backgroundLayer = CALayer.new;
		_backgroundLayer.anchorPoint = CGPointMake(0, 0);
		_backgroundLayer.position = CGPointMake(0, 0);
		_backgroundLayer.zPosition = -1;    /// this makes sure this layer shows behind our own layer
		_backgroundLayer.actions = @{kCAOnOrderIn: NSNull.null, kCAOnOrderOut: NSNull.null,
									 NSStringFromSelector(@selector(sublayers)): NSNull.null,
									 NSStringFromSelector(@selector(position)): NSNull.null};
		[self.superview.layer addSublayer:_backgroundLayer];
	}
	return _backgroundLayer;
}


- (BOOL)preservesContentDuringLiveResize {
	return YES;
}


+ (BOOL)isCompatibleWithResponsiveScrolling {
	return YES;
}


- (NSInteger)tag {
	return 1;
}


- (RulerView *)rulerView {
	if(!_rulerView) {
		NSScrollView *scrollView = self.enclosingScrollView;
		scrollView.rulersVisible = YES;
		RulerView *rulerView = RulerView.new;
		scrollView.horizontalRulerView = rulerView;
		rulerView.ruleThickness = ruleThickness;
		rulerView.reservedThicknessForMarkers = 0.0;
		rulerView.reservedThicknessForAccessoryView = markerViewHeight;
		rulerView.clientView = self;
		_rulerView = rulerView;
		
	}
	return _rulerView;
}


- (MarkerView *)markerView {
	if(!_markerView) {
		_markerView = MarkerView.new;
		self.rulerView.accessoryView = _markerView;
		[_markerView setFrameSize:NSMakeSize(_markerView.frame.size.width, markerViewHeight)];
	}
	return(_markerView);
}



#pragma mark - loading content

- (void)loadTraces:(NSArray<Trace *> *)traces {
	[self loadTraces:traces marker:nil];
	showMarkerOnly = NO;
}


- (void)loadSample:(Chromatogram *)sample {
	[self loadTraces:sample.traces.allObjects marker:nil];
	showMarkerOnly = NO;
}


- (void)loadGenotype:(Genotype *)genotype {
	Trace *trace = [genotype.sample traceForChannel:genotype.marker.channel];
	if(trace) {
		_genotype = genotype;
		[self loadTraces:@[trace] marker:genotype.marker];
	} else {
		_genotype = nil;
		[self loadTraces:nil marker:nil];
	}
	showMarkerOnly = NO;
}


- (void)loadMarker:(Mmarker *)marker {
	[self loadTraces:nil marker:marker];
	showMarkerOnly = YES;
}

/// loads the specified traces and the marker
- (void)loadTraces:(nullable NSArray<Trace *> *)traces marker:(nullable Mmarker *)marker {
	
	/// We set the hScale to -1 to signify that our geometry is reset and not final. This is to prevent our range from being modified in resizeWithOldSuperViewSize: before prepareForDisplay: (the latter sets our hScale)
	_hScale = -1.0;
	_marker = marker;
	self.loadedTraces = traces;
	
	/// we determine the channel that we show
	/// we remember our previous channel to determine if we should load the panel or keep the previous one, as we only show markers associated with a single channel
	ChannelNumber previousChannel = self.channel;
	if(marker) {
		self.channel = marker.channel;
	} else {
		self.channel = traces.firstObject.channel;
	}
	
	if(traces.count == 5 || traces.count == 4) {
		/// in this situation, the traces may come from the same sample, hence have different channels
		for(Trace *trace in traces) {
			if(trace.channel != self.channel) {
				self.channel = -1;
				break;
			}
		}
	}
	
	if(traces.count == 0 || marker == nil) {
		_genotype = nil;
	}
	
	/// we pick our "trace" property among the traces. We take the longest.
	Trace *aTrace = traces.count > 0? traces.firstObject : nil;
	float maxReadLength = -1;		/// we don't use the @max operator, as it is much slower than an enumeration.
	for (Trace *trace in traces) {
		Chromatogram *chromatogram = trace.chromatogram;
		if (chromatogram.readLength > maxReadLength && chromatogram.sizingQuality) {
			maxReadLength = chromatogram.readLength;
			aTrace = trace;
		}
	}
	
	self.trace = aTrace;
	
	/// We set the panel of markers (even in case we show a single marker, we need to load others as marker resizing depends on other markers of the same channel)
	
	Panel *refPanel = [self panelToShow];
	
	/// we check if we should set the new panel. We may not if it is the same as before and if the channel hasn't changed
	/// this increases performance when switching between samples while the user scrolls (avoids hitches)
	/// but if we don't or didn't show a trace (hence only a marker), we always load the panel.
	/// this because the marker we highlight may be different (even if from the same panel and channel) and the way we show the panel also depends on whether we show traces
	if(showMarkerOnly || traces.count == 0 || previousChannel != self.channel || self.panel != refPanel || refPanel == nil) {
		self.panel = refPanel;
	} else {
		/// if we keep the panel (and all the associated labels), we need to update the label offset to the new genotypes shown.
		[self updateLabelOffsets];
		RegionLabel *enabledMarkerLabel = self.enabledMarkerLabel;
		if(enabledMarkerLabel.highlighted && enabledMarkerLabel.editState >= editStateShownSamples) {
			enabledMarkerLabel.enabled = NO;		/// if the user was editing an offset, we disable it.
													/// We must end the edition of the offset if the view's content has changed, because this edition may affect the sample(s) shown
		}
	}
	
	[self prepareForDisplay];
}

/// Returns the panel that we (and our marker view) may show.
///
/// We only show a label if only one channel is shown and if traces don't correspond to samples having different panels.
/// We don't show the panel is samples are not sized (no size standard, sizing failed...)
-(nullable Panel *)panelToShow {
	if(self.channel < 0) {
		return nil;
	}
	
	if(self.marker.panel && self.loadedTraces.count == 0) {
		return self.marker.panel;
	}
	
	Panel *refPanel = nil;
	for(Trace *trace in self.loadedTraces) {
		Chromatogram *sample = trace.chromatogram;
		if(sample.sizingQuality != nil) {				   /// we don't show the panel from a sample that is not sized
			if(sample.panel != refPanel && refPanel != nil) {
				/// we won't show a panel if samples have different panels
				return nil;
			}
			refPanel = sample.panel;
		}
	}
	return refPanel;
}


- (void)setTrace:(Trace *)aTrace {
	_trace = aTrace;
	Chromatogram *sample = aTrace.chromatogram;
	_sampleStartSize = sample != nil? sample.startSize : 0.0;
	[self updateViewLength];
}



- (void)setLoadedTraces:(NSArray <Trace *>*)traces {
	/// as we observe some properties of our samples, we must stop observing previous samples
	[self stopObservingSamples];
	NSUInteger count = traces.count;
	if(count > 400) {
		traces = [traces objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 400)]];
	}
	_loadedTraces = traces;
	visibleTraces = traces;
	
	if(count == 0) {
		return;
	}
	
	Trace *firstTrace = traces.firstObject;
	BOOL oneSample = count > 1 && firstTrace.chromatogram == [traces.lastObject chromatogram];
	
	if(oneSample) {
		/// Here the traces all come from the same sample
		/// We determine which can be displayed (as they have different channels)
		visibleTraces = [traces filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Trace *trace, NSDictionary<NSString *,id> * _Nullable bindings) {
			return [self.displayedChannels containsObject: @(trace.channel)];
		}]];
	}
	
	if(oneSample || count == 1) {
		observedSamples = @[firstTrace.chromatogram];
	} else {
		observedSamples = [traces valueForKeyPath:@"@unionOfObjects.chromatogram"];
	}
	
	BOOL ladder = firstTrace.isLadder;
	if(!ladder && !oneSample) {
		observedSamplesForPanel = observedSamples;
	}
	
	for(Chromatogram *sample in observedSamples) {
		[sample addObserver:self forKeyPath:ChromatogramSizesKey options:NSKeyValueObservingOptionNew context:sampleSizingChangedContext];
		[sample addObserver:self forKeyPath:ChromatogramSizingQualityKey options:NSKeyValueObservingOptionNew context:sampleSizingChangedContext];
		
		if(!ladder && !oneSample) {
			/// if the trace is not a ladder, we observe the panel, as we show bins and communicate changes to the marker view.
			[sample addObserver:self forKeyPath:ChromatogramPanelKey options:NSKeyValueObservingOptionNew context:panelChangedContext];
		}
	}
}



-(void)stopObservingSamples {
	for(Chromatogram *sample in observedSamples) {
		[sample removeObserver:self forKeyPath:ChromatogramSizesKey];
		[sample removeObserver:self forKeyPath:ChromatogramSizingQualityKey];
	}
	observedSamples = nil;
	
	for(Chromatogram *sample in observedSamplesForPanel) {
		[sample removeObserver:self forKeyPath:ChromatogramPanelKey];
	}
	observedSamplesForPanel = nil;
}


- (void)clearContents {
	_trace = nil;
	self.loadedTraces = nil;
	_marker = nil;
	_genotype = nil;
}

#pragma mark - managing labels


+ (NSSet<NSString *> *)keyPathsForValuesAffectingMarkers {
	return [NSSet setWithObject:@"panel.markers"];
}


-(void)setPanel:(Panel *)panel {
	_panel = panel;
	NSArray *markersShown = [panel markersForChannel:self.channel];
	[self createLabelsForMarkers: markersShown];
}


-(void)panelMarkersDidChange:(NSNotification *)notification {
	Panel *panel = notification.object;
	if(panel != nil && panel == self.panel) {
		/// we just reload the whole panel if its markers have changed (which doesn't happen often), since we have to update for marker labels and bin labels
		self.panel = panel;
	}
}


-(void)updateLabelOffsets {
	if(self.markerLabels.count  > 0 && self.trace.chromatogram.genotypes.count > 0) {
		NSSet *genotypes = [self.trace.chromatogram genotypesForChannel:self.channel];
		for(Genotype *genotype in genotypes) {
			MarkerOffset offset = genotype.offset;
			Mmarker *marker = genotype.marker;
			for(RegionLabel *markerLabel in self.markerLabels) {
				if(markerLabel.region == marker) {
					markerLabel.offset = offset;
					break;
				}
			}
		}
	}
}



- (void)createLabelsForMarkers:(NSArray<Mmarker*> *)markers {
	NSMutableArray *temp = NSMutableArray.new;
	Chromatogram *sample = self.trace.chromatogram;
	for(Mmarker *marker in markers) {
		RegionLabel *traceMarkerLabel = [RegionLabel regionLabelWithRegion:marker view:self];
		if(sample) {
			Genotype *genotype = [sample genotypeForMarker:marker];
			if(genotype.offsetData) {
				traceMarkerLabel.offset = genotype.offset;
			}
		}
		
		[temp addObject:traceMarkerLabel];
	}
	
	self.markerLabels = [NSArray arrayWithArray:temp];
	
}


-(void)setMarkerLabels:(NSArray *)markerLabels {
	for(RegionLabel *label in _markerLabels) {
		if([markerLabels indexOfObjectIdenticalTo:label] == NSNotFound) {
			[label removeFromView];
		}
	}
	_markerLabels = markerLabels;
	if(self.markerLabels.count > 0) {
		self.needsLayoutLabels = YES;
	}
	
	self.binLabels = [markerLabels valueForKeyPath:@"@unionOfArrays.binLabels"];
	
	[self.markerView updateContent];
}


-(void)markerBinsDidChange:(NSNotification *)notification {
	if(doNotCreateLabels) {
		return;
	}
	
	Mmarker *marker = notification.object;
	
	for(RegionLabel *markerLabel in self.markerLabels) {
		if(markerLabel.region == marker) {
			[markerLabel resetBinLabels];
			/// We replace all the bin labels in the array, which is easier than replacing those from the marker that has changed specifically.
			self.binLabels = [self.markerLabels valueForKeyPath:@"@unionOfArrays.binLabels"];
			break;
		}
	}
}


- (void)setBinLabels:(NSArray *)binLabels {
	for(RegionLabel *label in _binLabels) {
		if([binLabels indexOfObjectIdenticalTo:label] == NSNotFound) {
			[label removeFromView];
		}
	}
	_binLabels = binLabels;
	if(binLabels.count > 0) {
		self.needsUpdateLabelAppearance = YES;
		self.needsLayoutLabels = YES;
	}
}


-(void)genotypeOffsetDidChange:(NSNotification *)notification {
	Genotype *genotype = notification.object;
	if(!genotype.sample || genotype.sample != self.trace.chromatogram) {
		return;
	}
	
	Mmarker *marker = genotype.marker;
	MarkerOffset offset = genotype.offset;
	
	for(RegionLabel *markerLabel in self.markerLabels) {
		if(markerLabel.region == marker) {
			markerLabel.offset = offset;
			[markerLabel reposition];
			for(RegionLabel *binLabel in markerLabel.binLabels) {
				[binLabel reposition];
			}
			break;
		}
	}
	
	self.rulerView.needsUpdateOffsets = YES;
}


- (void)setEnabledMarkerLabel:(RegionLabel *)markerLabel {
	if(markerLabel == _enabledMarkerLabel) {
		return;
	}
	if(_enabledMarkerLabel && _enabledMarkerLabel != markerLabel && !self.showDisabledBins && self.trace) {
		/// we hide bins of the previous enabled marker label if required
		for(RegionLabel *binLabel in _enabledMarkerLabel.binLabels) {
			binLabel.hidden = YES;
		}
	}
	_enabledMarkerLabel = markerLabel;
	if(_enabledMarkerLabel) {
		/// we disable peak and fragment labels as they may interfere
		for(PeakLabel *label in self.peakLabels) {
			label.enabled = NO;
		}
		for(FragmentLabel *label in self.fragmentLabels) {
			label.enabled = NO;
		}
		
		for(RegionLabel *binLabel in _enabledMarkerLabel.binLabels) {
			binLabel.hidden = NO;	/// bin labels of an enabled marker label are always visible
		}
	} else {
		for(FragmentLabel *label in self.fragmentLabels) {	/// if the marker is no longer edited, we (re-)enable labels
			label.enabled = YES;
		}
		for(PeakLabel *label in self.peakLabels) {
			label.enabled = YES;
		}
	}
	if(self.showOffscaleRegions) {
		/// We redraw as we don't show off-scale regions when a marker label is enabled (to avoid interference with its rectangle and its bins).
		self.needsDisplay = YES;
	}
}


-(void)createFragmentLabels {
	NSMutableArray *temp = NSMutableArray.new;
	if(self.loadedTraces.count == 1) {
		BOOL disable = self.enabledMarkerLabel != nil;
		for (LadderFragment * fragment in self.trace.fragments) {
			FragmentLabel *label = [[FragmentLabel alloc] initFromFragment:fragment view:self];
			if(disable) {
				label.enabled = NO;
			}
			[temp addObject:label];
		}
	}
	self.fragmentLabels = [NSArray arrayWithArray:temp];
}


- (void)setFragmentLabels:(NSArray *)fragmentLabels {
	for(FragmentLabel *label in _fragmentLabels) {
		if([fragmentLabels indexOfObjectIdenticalTo:label] == NSNotFound) {
			[label removeFromView];
		}
	}
	_fragmentLabels = fragmentLabels;
	if(_fragmentLabels.count > 0) {
		self.needsLayoutLabels = YES;
	}
}


- (void)createPeakLabels {
	NSMutableArray *temp = NSMutableArray.new;
	NSData *peakData = self.trace.peaks;
	if(peakData && self.loadedTraces.count == 1) {
		BOOL disable = self.enabledMarkerLabel != nil;
		const Peak *peaks = peakData.bytes;
		long nPeaks = peakData.length / sizeof(Peak);
		for (int i = 0; i < nPeaks; i++) {
			PeakLabel *newPeak = [[PeakLabel alloc] initWithPeak:peaks[i] view:self];
			if(disable) {
				newPeak.enabled = NO;
			}
			[temp addObject:newPeak];
		}
	}
	self.peakLabels = [NSArray arrayWithArray:temp];
}


- (void)setPeakLabels:(NSArray *)peakLabels {
	for(RegionLabel *label in _peakLabels) {
		[label removeFromView];
	}
	_peakLabels = peakLabels;
	if(_peakLabels.count > 0) {
		self.needsLayoutLabels = YES;
	}
	/// labels call a needsDisplayInRect when they are positioned, but in case a previous label is deleted and was hovered/active, the view may not be redrawn in the rectangle, so:
	self.needsDisplay = YES;
}


- (void)labelDidChangeEnabledState:(ViewLabel *)label {
	if([label isKindOfClass: RegionLabel.class]) {
		RegionLabel *regionLabel = (RegionLabel *)label;
		if(regionLabel.isMarkerLabel) {
			if(regionLabel.enabled) {
				/// a marker label gets enabled via a menu, in which case our mouseLocation may not have been updated
				/// because -moveMoved is not called when the mouse is over the menu.
				/// So, the label does not becomes hovered although the mouse is over it when the menu closes.
				/// Hence we "manually" update of mouse location. This should make sure the cursor is correct
				self.mouseLocation =  [self convertPoint:NSApp.currentEvent.locationInWindow fromView:nil];
				self.enabledMarkerLabel = regionLabel;
			} else if(self.enabledMarkerLabel == regionLabel) {
				self.enabledMarkerLabel = nil;
			}
		}
	}
}


- (void)labelDidChangeHoveredState:(ViewLabel *)label {
	if([label isKindOfClass: RegionLabel.class]) {
		RegionLabel *regionLabel = (RegionLabel *)label;
		if(regionLabel.isMarkerLabel) {
			[super labelDidChangeHoveredState:label];
		} else if(regionLabel.isBinLabel) {
			if(label.hovered) {
				hoveredBinLabel = regionLabel;
			} else if(hoveredBinLabel == regionLabel) {
				hoveredBinLabel = nil;
			}
		}
		[self updateCursor];
	}
}

/// Returns all labels that are specific to the trace: peak and fragment labels.
- (NSArray *) traceLabels {
	/// It is important to place fragmentLabels first in the array.  When we send mouseDownInView message, this ensures that a fragment label becomes highlighted before the peak label at the same position.
	/// Because the activeLabel must remain the fragment label (we check this in labelChangedHighlightedState) rather than the peak label.
	/// If peakLabels came first, and if the user clicks a fragmentLabel that is already highlighted, the underlying peakLabel would become the active label. The fragment label would not as its state did not change
	return [self.fragmentLabels arrayByAddingObjectsFromArray: (NSArray *)self.peakLabels];		/// the (NSArray pointer cast is to avoid a warning as both arrays specify different types of objects)
}

/// Returns bin labels and marker labels.
- (NSArray *) panelLabels {
	NSArray *binLabels = self.binLabels;
	if(!binLabels) {
		binLabels = NSArray.new;
	}
	return [binLabels arrayByAddingObjectsFromArray:self.markerLabels];
	
}


- (NSArray *) viewLabels {
	return [self.traceLabels arrayByAddingObjectsFromArray:self.panelLabels];
}


- (NSArray<ViewLabel *> *)repositionableLabels {
	return [self.panelLabels arrayByAddingObjectsFromArray:self.fragmentLabels];
}


- (void)setNeedsLayoutFragmentLabels:(BOOL)needsLayoutFragmentLabels {
	_needsLayoutFragmentLabels = needsLayoutFragmentLabels;
	if(needsLayoutFragmentLabels) {
		self.needsLayout = YES;
	}
}


-(void)layout {
	if(self.needsLayoutFragmentLabels && !self.needsLayoutLabels && self.hScale >=0) {
		/// we don't need to reposition fragment labels here if all labels will be repositioned anyway (in super)
		BOOL animated = NSAnimationContext.currentContext.allowsImplicitAnimation;
		for(FragmentLabel *label in self.fragmentLabels) {
			label.animated = animated;
			[label reposition];
			label.animated = YES;
		}
	}
	[super layout];
	self.needsLayoutFragmentLabels = NO;
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if(context == displaySettingsChangedContext) {
		self.needsDisplay = YES;
	} else if(context == sampleSizingChangedContext) {
		Chromatogram *sample = object;
		if(sample.coefs != nil) {
			/// we only react if the sizing properties haven't become nil (which may happen)
			if(sample == self.trace.chromatogram) {
				if([keyPath isEqualToString:ChromatogramSizesKey]) {
					[self updateViewLength];
					[self fitToIntrinsicContentSize];
					self.needsLayoutLabels = YES;
				} else if([keyPath isEqualToString:ChromatogramSizingQualityKey]){
					/// If sizing has changed, sizing may have failed for samples we show or may have become valid instead
					/// Since we don't show a panel when sizing has failed, we may need to update the panel we show
					Panel *panel = [self panelToShow];
					if(panel != self.panel) {
						self.panel = panel;
					}
				}
			}
			self.needsDisplay = YES;
			self.rulerView.needsDisplay = YES;
		}
	} else if(context == panelChangedContext) {
		/// we reload the whole panel if it has changed
		Panel *panel = [self panelToShow];
		if(panel != self.panel) {
			self.panel = panel;
		}
	} else if(context == fragmentsChangedContext) {
		[self createFragmentLabels];
	} else if(context == peakChangedContext) {
		[self createPeakLabels];
	}
	else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	
}


# pragma mark - drawing commands


- (void)drawRect:(NSRect)dirtyRect {
	
	
	if(self.needsUpdateLabelAppearance) {
		/// if this method is called because the app theme has changed, we must change the bin labels, whose appearance depends on the theme.
		for(RegionLabel *label in self.binLabels) {
			[label updateForTheme];
		}
		self.needsUpdateLabelAppearance = NO;
	}
	
	/// we draw traces
	if(visibleTraces.count > 0) {
		[self drawTracesInRect:dirtyRect];
	}
}

/// Draws trace-related elements in the view. Called during drawRect:
- (void)drawTracesInRect:(NSRect) dirtyRect {
	float hScale = self.hScale;
	float vScale = self.vScale;
	float sampleStartSize = self.sampleStartSize;
	float vOffset = self.verticalOffset;
	float startSize = dirtyRect.origin.x/hScale + sampleStartSize;	/// the size (in base pairs) at the start of the dirty rect
	float endSize = NSMaxX(dirtyRect)/hScale + sampleStartSize;
	Chromatogram *sample = self.trace.chromatogram;
	const float *sizes = sample.sizes.bytes;
	long nScans = sample.sizes.length / sizeof(float);
	if(nScans == 0) {
		return;
	}
	
	/// We show offscale regions (with vertical grey rectangles)
	/// We don't drawn them if we have traces from several samples and if a marker label is enabled, as these regions can mask the edges  of this label or its bin labels
	NSData *offscaleRegions = sample.offscaleRegions;
	if (self.showOffscaleRegions && offscaleRegions.length > 0 && (visibleTraces.count == 1 || self.channel == -1) && !self.enabledMarkerLabel) {
		/// channel is normally -1 if we show traces for the same sample. In this case, we can draw off-scale regions
		const OffscaleRegion *regions = offscaleRegions.bytes;
		for (int i = 0; i < offscaleRegions.length/sizeof(OffscaleRegion); i++) {
			OffscaleRegion region = regions[i];
			if(region.startScan + region.regionWidth >= nScans) {
				break;
			}
			float regionStart = sizes[region.startScan];
			float regionEnd = sizes[region.startScan + region.regionWidth];
			if (regionEnd >= startSize && regionStart <= endSize) {
				NSColor *color = self.colorForOffScaleScans[region.channel];
				[color setFill];
				float x1 = (regionStart - sampleStartSize) * hScale;
				float x2 = (regionEnd - sampleStartSize) * hScale;
				float scanWidth = (x2-x1)/region.regionWidth;
				/// we place the rectangle at half a scan to the left, so that it is centered around the saturated scans
				NSRectFill(NSMakeRect(x1 - scanWidth/2, 0, x2-x1, NSMaxY(self.bounds)));
			}
		}
	}
	
	
	/// we draw the fluorescence curve(s) as paths of connected line segments.
	/// Curves are drawn from left to right.
	/// optimisations: we skip points of height less than 1 pt and just draw a straight line at y = vOffset,
	/// except when neighboring points that are at y > 1pt (or else the line would not be parallel to the edge).
	/// Since most of the trace has low fluorescence (especially with baseline level subtracted), this saves a lot of time
	/// we skip points that are less than x = 1 pt away from a previous point, except for local maxima/minima (or else peaks gets borked).
	/// This improves performance at low zoom scale, when paths are long and this is hardly noticeable
	/// we stroke the path every few dozens of points, since long paths kill performance
	
	CGFloat lowerPoint = threshold;
	short lowerFluo = threshold / vScale; 	/// to quickly evaluate if some scans should be drawn
	
	float xFromLastPoint = 0;  				/// the number of quartz points from the last added point, which we use to determine if a scan can be skipped
	float lastX = 0;
	int maxPointsInCurve = 40;					/// we stoke the curve if it has enough points. Numbers between 10-100 seem to yield the best performance
	NSPoint pointArray[maxPointsInCurve];          /// points to add to the curve
	int totPoints = 0, totDrawn = 0, skipped = 0;	/// variables used for performance reports. We skip some scans for performance without much impact on fidelity
	int startScan = 0, maxScan = 0, lastScan = 0;	/// we will draw traces for scan between these scans.
	sample = nil;
	
	for (Trace *traceToDraw in visibleTraces) {
		NSData *fluoData = _showRawData? traceToDraw.primitiveRawData : [traceToDraw adjustedDataMaintainingPeakHeights:_maintainPeakHeights];
		const int16_t *fluo = fluoData.bytes;
		long nRecordedScans = fluoData.length/sizeof(int16_t);
		if(nRecordedScans > nScans) {
			nRecordedScans = nScans;
		}
		Chromatogram *theSample = traceToDraw.chromatogram;
		if(theSample != sample) {
			/// this condition avoids repeating the instruction below, as traces from the same chromatogram have the same sizing properties
			sample = theSample;
			sizes = sample.sizes.bytes;
			
			/// we never draw scans that are after the maxScan, as they have lower sizes than the maxScan.
			/// The curve would go back to the left and overlap itself
			maxScan = sample.maxScan;
			
			/// the first scan for which me may draw the fluorescence is the one at the left of the dirty rect
			startScan = [sample scanForSize:startSize]-1;
			if(startScan < sample.minScan) {
				/// but for the reason stated above, we don't draw scans before the minScan
				startScan = sample.minScan;
			}
			if(maxScan <= nRecordedScans) {
				maxScan = (int)nRecordedScans -1;
			}
		}
		
		[self.colorsForChannels[traceToDraw.channel] setStroke];
		short pointsInPath = 0;		/// current number of points being added to the path
		bool outside = false;		/// whether a scan is to the right (outside) the dirty rect. Used to determine when to stop drawing.
		int scan = startScan;
		while(scan <= maxScan && !outside) {
			totPoints++;
			if(sizes[scan] > endSize) {
				outside = true;
				lastScan = scan;
			}
			float x = (sizes[scan] - sampleStartSize) * hScale;
			xFromLastPoint = x - lastX;
			
			int16_t scanFluo = fluo[scan];
			if (scan != startScan && !outside && scan < maxScan-1) {
				/// to skip a scan, it must not be the first nor last. We have to draw the first point outside the dirty rect as well.
				if(!(scanFluo <= lowerFluo && (fluo[scan-1] > lowerFluo || fluo[scan+1] > lowerFluo))) { 			// the point must not be the first/last of a series of scans under the lower threshold
					if(scanFluo < lowerFluo ||
					   /// we can skip any remaining scan below the fluo threshold
					   (xFromLastPoint < 1 && !(fluo[scan-1] >= scanFluo && fluo[scan+1] > scanFluo) && !(fluo[scan-1] <= scanFluo && fluo[scan+1] < scanFluo))) {
						/// or any that is too close from previously drawn scans and not a local minimum / maximum
						scan++;
						skipped++;
						continue;
					}
				}
			}
			lastX = x;
			float y = scanFluo * vScale;
			if (y < lowerPoint) y = lowerPoint -1;
			pointArray[pointsInPath++] = CGPointMake(x, y + vOffset);
			
			if (pointsInPath == maxPointsInCurve || outside || scan == maxScan-1) {
				totDrawn += pointsInPath;
				[curve appendBezierPathWithPoints:pointArray count:pointsInPath];
				[curve stroke];
				[curve removeAllPoints];
				pointArray[0] = pointArray[pointsInPath-1];
				/// the first point in the next path is the last of the previous path. If we don't do that, there is a gap between paths.
				pointsInPath = 1;
			}
			scan++;
		}
		
	}
	
	///we draw peak labels, which don't use CALayers
	for (PeakLabel *label in self.peakLabels) {
		if (label.endScan >= startScan) {
			if(label.startScan > lastScan || label.endScan > maxScan) {
				break;
			}
			[label draw];
		}
	}
}


- (CGFloat) xForScan:(uint) scan {
	float size = [self.trace.chromatogram sizeForScan:scan];
	return (size - _sampleStartSize) * _hScale;
}


- (CGPoint) pointForScan:(uint)scan {
	Trace *trace = self.trace;
	
	if(!trace) {
		return CGPointMake(0, 0);
	}
	
	NSData *fluoData = _showRawData? trace.primitiveRawData : [trace adjustedDataMaintainingPeakHeights: _maintainPeakHeights];
	
	if(scan >= fluoData.length/sizeof(int16_t)) {
		return CGPointMake(0, 0);
	}
	
	const int16_t *fluo = fluoData.bytes;
	return CGPointMake([self xForScan:scan], fluo[scan] * _vScale + _verticalOffset);
}


- (int) scanForX:(float) position {
	return [self.trace.chromatogram scanForSize:(position/_hScale + _sampleStartSize)];
}


#pragma mark - scale and scrolling management


- (void)setVisibleRange:(BaseRange)range {
	if(range.len < 0) {
		range.start += range.len;
		range.len = -range.len;
	}
	if (range.start != _visibleRange.start | range.len != _visibleRange.len) {
		_visibleRange = range;
		float newScale = self.visibleWidth / _visibleRange.len;
		self.hScale = newScale;
		self.visibleOrigin = (range.start - _sampleStartSize) * _hScale;
		[self.delegate traceViewDidChangeRangeVisibleRange:self];
		
	}
	if(!self.marker)  {
		for(Trace *trace in self.loadedTraces) {
			trace.visibleRange = _visibleRange;
		}
	}
}


- (void)setVisibleRangeAndDontNotify:(BaseRange)range {
	/// this is the same setVisibleRange, only without the message sent to the delegate
	/// setVisibleRange could call this method, but this would require more work for a method that is called quite often
	if(range.len < 0) {
		range.start += range.len;
		range.len = -range.len;
	}
	if (range.start != _visibleRange.start | range.len != _visibleRange.len) {
		_visibleRange = range;
		float newScale = self.visibleWidth / _visibleRange.len;
		self.hScale = newScale;
		self.visibleOrigin = (_visibleRange.start - _sampleStartSize) * _hScale;
		if(resizingTimer.valid) {
			[resizingTimer invalidate];
		}
		resizingTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(doneMoving) userInfo:nil repeats:NO];
		[[NSRunLoop mainRunLoop] addTimer:resizingTimer forMode:NSRunLoopCommonModes];
		self.isMoving = YES;
	}
	if(!self.marker)  {
		for(Trace *trace in self.loadedTraces) {
			trace.visibleRange = _visibleRange;
		}
	}
}


- (void)setTopFluoLevel:(float)fluo {
	if(_topFluoLevel != fluo && fluo > 0) {
		if(fluo > 35000) {
			fluo = 35000;
		} else if(fluo < 20) {
			fluo = 20;
		}
		_topFluoLevel = fluo;
		if(self.genotype) {
			self.genotype.topFluoLevel = fluo;
		} else {
			for(Trace *trace in self.loadedTraces) {
				trace.topFluoLevel = fluo;
			}
		}
		if(self.frame.size.height > 0) {
			self.vScale = self.frame.size.height/_topFluoLevel;
		}
		[self.delegate traceViewDidChangeTopFluoLevel:self];
	}
}


- (void)setTopFluoLevelAndDontNotify:(float)fluo {
	if(_topFluoLevel != fluo && fluo > 0) {
		if(fluo > 35000) {
			fluo = 35000;
		} else if(fluo < 20) {
			fluo = 20;
		}
		_topFluoLevel = fluo;
		if(self.genotype) {
			self.genotype.topFluoLevel = fluo;
		} else {
			for(Trace *trace in self.loadedTraces) {
				trace.topFluoLevel = fluo;
			}
		}
		if(self.frame.size.height > 0) {
			self.vScale = self.frame.size.height/_topFluoLevel;
		}
	}
}


- (void)setVScale:(float)scale {
	if (scale != _vScale) {
		_vScale = scale;
		self.needsDisplay = YES;
		self.vScaleView.needsDisplay = YES;
		self.needsLayoutFragmentLabels = YES;
	}
}


- (void)setVisibleOrigin:(float)newVisibleOrigin {
	if (newVisibleOrigin != _visibleOrigin) {
		/// as our markerView doesn't scroll, it needs to reposition its marker labels to reflect our range
		self.markerView.needsLayoutLabels = YES;
		
		/// we set the current mouse location in the view coordinate system as it changes during scrolling
		/// (since the view scrolls behind the mouse) and should show in the ruler view
		/// to compute it, we need to record the previous visible origin (the new mouse location must set it after the scroll)
		float previous = _visibleOrigin;
		_visibleOrigin = newVisibleOrigin;
		
		NSClipView *clipView = (NSClipView *)self.superview;
		if (clipView.bounds.origin.x != newVisibleOrigin) {
			[clipView scrollToPoint:NSMakePoint(newVisibleOrigin, 0)];
			[self.enclosingScrollView reflectScrolledClipView:clipView];
		}
		
		if(mouseIn) {
			/// We could determine the mouse location "de novo" using the NSWindow method,
			/// but this would use more resources, considering that this is called at every scroll step.
			/// It's important to update the mouse location after the scrolling, otherwise it is not reported correctly in the ruler view during a zoom.
			NSPoint location = _mouseLocation;
			location.x += newVisibleOrigin - previous;
			self.mouseLocation = location;
		}
	}
}


- (void)setHScale:(float)newScale {
	if (newScale != self.hScale) {
		if(newScale > maxHScale) {
			newScale = maxHScale;
		}
		_hScale = newScale;
		[self fitToIntrinsicContentSize];
		self.markerView.needsLayoutLabels = YES;
	}
}


/// Makes the view as wide as it needs to be,
- (void)fitToIntrinsicContentSize {
	NSSize newSize = self.intrinsicContentSize;
	if (!NSEqualSizes(newSize, self.frame.size)) {
		self.isResizing = YES;
		[self setFrameSize:newSize];
		self.isResizing = NO;
	}
	self.needsDisplay = YES;
}




#pragma mark - zooming

- (void)setVisibleRange:(BaseRange)visibleRange animate:(BOOL)animate  {
	if(visibleRange.len < 0) {
		visibleRange.start += visibleRange.len;
		visibleRange.len = -visibleRange.len;
	}
	if(animate) {
		BaseRange current = self.visibleRange;
		/// we set the start value of the animatable range to the current range
		NSSize currentRange = NSMakeSize(current.start, current.len);
		_animatableRange = currentRange;
		self.animator.animatableRange = NSMakeSize(visibleRange.start, visibleRange.len);
		if(self.autoScaleToHighestPeak) {
			/// if we autoscale to the highest peak, we take advantage of the fact that we know the final range,
			/// hence we animate the change in vertical scale in sync
			float targetFluo = [self topFluoForRange:visibleRange];
			if(targetFluo > 0) {
				/// if a peak is in the range, we change the scale
				self.animator.topFluoLevel = targetFluo;
			}
		}
		[self.delegate traceView:self didStartMovingToRange:visibleRange];
	} else {
		self.visibleRange = visibleRange;
	}
}


- (void)setAnimatableRange:(NSSize)animatableRange {
	self.visibleRange = MakeBaseRange(animatableRange.width, animatableRange.height);;
}


- (void)zoomTo:(float)zoomPoint withFactor:(float)zoomFactor animate:(BOOL)animate {
	/// We prevent negative or null zoom factors that may happen if the user zooms too fast.
	if (zoomFactor <= 0) {
		zoomFactor = 0.01;
	}
	/// The position in base pairs that is under the mouse and should remain that way
	float zoomPosition = [self sizeForX:zoomPoint];
	float newStart = zoomPosition - (zoomPosition - self.visibleRange.start) / zoomFactor;
	float newRangeLength = self.visibleRange.len/zoomFactor;
	

	/// we prevent showing what is past the end of the view during zoom out
	if(newStart + newRangeLength > _sampleStartSize + viewLength) {
		newStart = viewLength + _sampleStartSize - newRangeLength;
	}
	
	if(newStart < _sampleStartSize) {
		newStart = _sampleStartSize;
	}
	
	if (newRangeLength > viewLength) {
		newRangeLength = viewLength;  ///the range cannot be wider than the whole view
	}
	float maxRange = self.visibleWidth / maxHScale; /// we constrain zooming to a max level
	if (newRangeLength < maxRange) {
		newRangeLength = maxRange;
	}
	
	if(self.visibleRange.len == newRangeLength && newRangeLength == maxRange) {
		/// this is required to stop zooming when the max zoom factor is reached (this method would induce some unwanted scrolling otherwise)
		return;
	}
	[self setVisibleRange:MakeBaseRange(newStart, newRangeLength) animate:animate];
}


- (void)zoomFromSize:(float)start toSize:(float)end {
	[self setVisibleRange:MakeBaseRange(start, end-start) animate:YES];
}



- (void)zoomToMarkerLabel:(RegionLabel *)markerLabel {
	
	BaseRange markerRange = [self baseRangeForMarkerLabel:markerLabel];
	[self setVisibleRange:markerRange animate:YES] ;
}


- (void)zoomToMarker {
	[self setVisibleRange:self.ourMarkerRange animate:YES];
}


- (BaseRange)ourMarkerRange {
	
	float start = self.marker.start;
	float end = self.marker.end;
	if(self.genotype) {
		MarkerOffset offset = self.genotype.offset;
		start = start * offset.slope + offset.intercept;
		end = end * offset.slope + offset.intercept;
	}
	BaseRange range = MakeBaseRange(start, end-start);
	if(self.markerView) {
		
		/// if we have a marker view, we use a wider range to make the marker show in full between the navigation buttons
		range = [self.markerView safeRangeForBaseRange:range];
	}
	return range;
}


- (BaseRange)baseRangeForMarkerLabel:(RegionLabel *)markerLabel {
	float startSize = markerLabel.startSize;
	BaseRange range = MakeBaseRange(startSize, markerLabel.endSize - startSize);
	if(self.markerView) {
		/// if we have a marker view, we use a wider range to make the marker show in full between the navigation buttons
		return [self.markerView safeRangeForBaseRange:range];
	}
	return range;
}



#pragma mark - setting frame, visible range, and other display attributes

/// This sets the visible range and vertical scale after the content is loaded
- (void)prepareForDisplay {
	/// we change ivars related to geometry to signify the the view is not in its final state. We don't use the setters as we don't want the view to actually change the geometry of the view to match these dummy values
	_hScale = -1.0; height = 0; _visibleRange = MakeBaseRange(0, 2.0);
	_topFluoLevel = -1;
	self.isMoving = NO;
	
	/// we determine the visible range of the trace(s) or the marker
	BaseRange refRange;
	if(self.marker) {
		/// if we show a genotype or just a marker, we show the range of the marker
		refRange = self.ourMarkerRange;
	} else {
		/// else we ask our delegate
		refRange = [self.delegate visibleRangeForTraceView:self];
	}
	
	/// we set the vertical scale of the fluorescence curves
	/// the first time the view shows, it doesn't have the proper height (doesn't fill the clipView's visible rectangle)
	[self fitVertically];
	float topFluoLevel = 1000;  /// we set an arbitrary default fluo level
	
	Trace *trace = self.trace;
	if(trace) {
		if(!self.autoScaleToHighestPeak) {
			topFluoLevel = [self.delegate topFluoLevelForTraceView:self];
		}
		if(topFluoLevel <= 0 || self.autoScaleToHighestPeak) {
			topFluoLevel = [self topFluoForRange:refRange];
			if(topFluoLevel <= 0) {
				/// if no peak was detected, we return the max fluo across all traces
				topFluoLevel = [[visibleTraces valueForKeyPath:@"@max.maxFluo"] floatValue];
			}
		}
	}
	
	[self setTopFluoLevelAndDontNotify:topFluoLevel];
	
	/// we directly set the visible range of the view. We don't use the setVisibleRange: method as we don't want to fire the resizingTimer
	if (refRange.start != _visibleRange.start | refRange.len != _visibleRange.len) {
		_visibleRange = refRange;
		float newScale = self.visibleWidth / _visibleRange.len;
		self.hScale = newScale;
		self.visibleOrigin = (_visibleRange.start - _sampleStartSize) * _hScale;
	}
	for(Trace *trace in self.loadedTraces) {
		trace.visibleRange = _visibleRange;
	}
	
	self.markerView.hidden = (trace && self.channel < 0) || trace.isLadder;
	
	self.needsLayoutLabels = YES;
	self.rulerView.needsUpdateOffsets = YES;
}


- (void)setBoundsOrigin:(NSPoint)newOrigin {
	/// we set our bounds origin to adapt to the presence of vScaleView, which overlaps us.
	/// our bounds x origin must be reflected by the top ruler view and the marker view, or else graduation and markers will not show at the correct position relative to the traces
	[super setBoundsOrigin:newOrigin];
	[self.markerView setBoundsOrigin:NSMakePoint(newOrigin.x, 0)];
	[self.rulerView setBoundsOrigin:NSMakePoint(newOrigin.x, 0)];
	self.backgroundLayer.position = CGPointMake(-newOrigin.x, 0);
	self.needsDisplay = YES;		/// this should not be required in principle, but when the view is zoomed out (and only then) changing the bounds somehow doesn't update the layer
	self.needsLayoutLabels = YES;
	
}


- (NSRect)visibleRect {
	/// overridden as our vScale view hides part of our left region, which ends at our x bounds origin of 0.
	/// So this region is removed from our visible rect;
	NSRect rect = super.visibleRect;
	rect.origin.x -= self.bounds.origin.x;
	rect.size.width += self.bounds.origin.x;
	if(rect.size.width < 0) {
		rect.size.width = 0;
	}
	return rect;
}


/// The width of the visible rectangle (in points), subtracting the region masked by the vscale view.
- (float) visibleWidth {
	return self.superview.frame.size.width + self.bounds.origin.x;
}


- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
	/// we react to changes in our clipview size to maintain our visible range and fit vertically to this view
	if(self.hScale <= 0.0) {
		return;  				/// we do not react when our visible range is not yet set
	}
	
	[self fitVertically];		/// we adjust to our clipview height
	
	self.hScale = self.visibleWidth / _visibleRange.len;;
	self.visibleOrigin = (_visibleRange.start - _sampleStartSize) * _hScale;
}


+(id)defaultAnimationForKey:(NSAnimatablePropertyKey)key {
	/// animations we use when zooming and changing the vertical scale
	if([animatableKeys containsObject:key]) {
		CABasicAnimation *animation = CABasicAnimation.animation;
		animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault];
		return animation;
	}
	return [super defaultAnimationForKey:key];
}


- (void)fitVertically {
	/// as we don't scroll vertically, we make sure our height is that of the visible rect in our clipview
	/// we have to consider the height of the horizontal ruler, which overlaps our clipView. We don't want to show behind that
	float topInset = 0;
	RulerView *rulerView = self.rulerView;
	NSRect clipViewFrame = self.superview.frame;
	if(rulerView && !rulerView.hidden) {
		topInset = NSIntersectionRect(rulerView.frame, clipViewFrame).size.height;
	}
	
	height = round(clipViewFrame.size.height - topInset);
	if(self.topFluoLevel > 0) {
		self.vScale = height/self.topFluoLevel;
	}
	if(height != self.frame.size.height) {
		[self setFrameSize:NSMakeSize(self.frame.size.width, height)];
		if(dashedLineLayer) {
			/// we make the dashed line layer as tall as the view
			dashedLineLayer.bounds = CGRectMake(0, 0, 1, height);
			CGMutablePathRef path = CGPathCreateMutable();
			CGPathMoveToPoint(path, NULL, 0.5, NSMaxY(dashedLineLayer.bounds));
			CGPathAddLineToPoint(path, NULL, 0.5,0);
			dashedLineLayer.path = path;
			CGPathRelease(path);
		}
	}
}


-(float)topFluoForRange:(BaseRange)range {		
	int16_t maxLocalFluo = 0;
	float startSize = range.start, endSize = range.start + range.len;
	BOOL useRawData = self.showRawData || self.maintainPeakHeights;
	BOOL ignoreCrosstalk = self.ignoreCrosstalkPeaks;
	
	for (Trace *trace in visibleTraces) {
		NSData *tracePeaks = trace.peaks;
		if(!tracePeaks) {
			/// we do not determine the maximum fluorescence by scanning all the data. We use peaks annotated in traces.
			continue;
		}
		Chromatogram *sample = trace.chromatogram;
		const float *sizes = sample.sizes.bytes;
		long nSizes = sample.sizes.length / sizeof(float);
		const Peak *peaks = tracePeaks.bytes;
		long nPeaks = tracePeaks.length/sizeof(Peak);
		int minScan = sample.minScan, maxScan = sample.maxScan;
		NSData *fluoData = useRawData? trace.primitiveRawData : [trace adjustedDataMaintainingPeakHeights:NO];
		NSInteger nScans = fluoData.length/sizeof(int16_t);
		const int16_t *fluo = fluoData.bytes;
		for(int i = 0; i < nPeaks; i++) {
			Peak peak = peaks[i];
			if(ignoreCrosstalk && peak.crossTalk < 0) {
				continue;
			}
			int scan = peak.startScan + peak.scansToTip;
			if(peakEndScan(peak) > maxScan || scan >= nSizes || sizes[scan] > endSize || scan >= nScans) {
				break;
			}
			if(peak.startScan < minScan || sizes[scan] < startSize) {
				continue;
			}
			
			if(fluo[scan] > maxLocalFluo) {
				maxLocalFluo = fluo[scan];
			}
		}
	}
	
	
	maxLocalFluo += maxLocalFluo * 20/self.frame.size.height;		/// we leave a 20-point margin above the highest peak
	return maxLocalFluo;
}


- (void)setTopFluoLevel:(float)fluo withAnimation:(BOOL)animate {
	if(!animate) {
		self.topFluoLevel = fluo;
	} else {
		self.animator.topFluoLevel = fluo;
	}
}


-(void) scaleToHighestPeakWithAnimation:(BOOL) animate {
	if(visibleTraces.count == 0) {
		return;
	}
	
	float fluo = [self topFluoForRange:self.visibleRange];
	if(fluo != self.topFluoLevel && fluo > 0) {
		[self setTopFluoLevel:fluo withAnimation:animate];
	}
}


- (void)updateViewLength {
	float maxEndSize = self.defaultRange.start + self.defaultRange.len;
	Trace *trace = self.trace;
	float length = trace == nil? 600.0 : trace.chromatogram.readLength;
	viewLength = (maxEndSize > length) ? maxEndSize - _sampleStartSize : length - _sampleStartSize;
}


- (NSSize)intrinsicContentSize {		
	return NSMakeSize(viewLength * self.hScale - self.bounds.origin.x, height);
}


-(void)setIsMoving:(BOOL)state {
	if(_isMoving != state) {
		_isMoving = state;
		if(state) {
			/// when the view gets resized, we remove tracking areas. During zoom, we don't reposition the areas, so their position is invalid.
			/// After resizing, they will be rebuilt
			for(NSTrackingArea *area in self.trackingAreas) {
				if(area != trackingArea) {
					[self removeTrackingArea:area];
				}
			}
		}
	}
}



# pragma mark - changes in display settings

- (void)setViewAppearance:(NSAppearance *)appearance {
	self.needsUpdateLabelAppearance = YES;
	/// we tell other views of the row to update their appearance.
	self.markerView.needsUpdateLabelAppearance = YES;
	self.rulerView.needsChangeAppearance = YES;
}


- (void)setShowDisabledBins:(BOOL)showBins {
	_showDisabledBins = showBins;
	if(!self.trace) {		/// we do not modify bin visibility if we only show a marker
							/// the bins of the marker we show are always visible
		return;
	}
	for (RegionLabel *markerLabel in self.markerLabels) {
		if((markerLabel.enabled) && !showBins) {
			/// we don't hide bins if the marker label is enabled.
			continue;
		}
		for(RegionLabel *label in markerLabel.binLabels) {
			label.hidden = !showBins;
		}
	}
}


- (void)setShowOffscaleRegions:(BOOL)showOffscaleRegions {
	_showOffscaleRegions = showOffscaleRegions;
	if(_hScale > 0) {
		/// offScale regions are drawn in -drawRect, so:
		self.needsDisplay = YES;
	}
}


- (void)setShowPeakTooltips:(BOOL)showPeakTooltips {
	_showPeakTooltips = showPeakTooltips;
	if(showPeakTooltips) {
		for (PeakLabel *label in self.peakLabels) {
			[label updateTrackingArea];
		}
	} else {
		[self removeAllToolTips];
	}
}


- (void)setShowRawData:(BOOL)showRawData {
	_showRawData = showRawData;
	if(self.autoScaleToHighestPeak) {
		[self scaleToHighestPeakWithAnimation:YES];
	}
	self.needsLayoutFragmentLabels = YES; /// because peak heights may change
	self.needsDisplay = YES;
}


- (void)setMaintainPeakHeights:(BOOL)maintainPeakHeights {
	_maintainPeakHeights = maintainPeakHeights;
	if(self.autoScaleToHighestPeak) {
		[self scaleToHighestPeakWithAnimation:YES];
	}
	self.needsLayoutFragmentLabels = YES; /// because peak heights may change
	self.needsDisplay = YES;
}


- (void)setAutoScaleToHighestPeak:(BOOL)autoScaleToHighestPeak {
	_autoScaleToHighestPeak = autoScaleToHighestPeak;
	if(autoScaleToHighestPeak) {
		[self scaleToHighestPeakWithAnimation:YES];
	}
}


- (void)setIgnoreCrosstalkPeaks:(BOOL)ignoreCrossTalkPeaks {
	_ignoreCrosstalkPeaks = ignoreCrossTalkPeaks;
	if(self.autoScaleToHighestPeak) {
		[self scaleToHighestPeakWithAnimation:YES];
	}
}


- (void)setColorsForChannels:(NSArray<NSColor *> *)colorForChannels {
	[super setColorsForChannels:colorForChannels];
	_colorForOffScaleScans = nil;
	self.needsDisplay = YES;
}


- (NSArray<NSColor *> *)colorForOffScaleScans {
	if(!_colorForOffScaleScans) {
		_colorForOffScaleScans = NSArray.new;
		for (NSColor *color in self.colorsForChannels) {		/// the offscale color as derived from channel color, but brighter
			_colorForOffScaleScans = [_colorForOffScaleScans arrayByAddingObject:[color blendedColorWithFraction:0.8 ofColor: NSColor.whiteColor]];
		}
	}
	return _colorForOffScaleScans;
}


- (void)setDisplayedChannels:(NSArray<NSNumber *> *)displayedChannels  {
	NSArray *previousTraces = visibleTraces;
	_displayedChannels = [NSArray arrayWithArray:displayedChannels];
	if(self.loadedTraces) {		
		visibleTraces = [self.loadedTraces filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Trace *trace, NSDictionary<NSString *,id> * _Nullable bindings) {
			return [self.displayedChannels containsObject: @(trace.channel)];
		}]];
		self.needsDisplay = YES;
		if(self.autoScaleToHighestPeak) {
			/// when displayed traces change, we may have to rescale to the highest peak
			/// we animate only if at least one trace was displayed before
			BOOL animate = NO;
			for(id obj in visibleTraces) {
				if([previousTraces indexOfObjectIdenticalTo:obj] != NSNotFound) {
					animate = YES;
					break;
				}
			}
			[self scaleToHighestPeakWithAnimation:animate];
		}
	}
}


- (void)setVerticalOffset:(float)verticalOffset {
	if(verticalOffset < 0.0) {
		verticalOffset = 0.0;
	} else if(verticalOffset > 100.0) {
		verticalOffset = 100.0;
	}
	_verticalOffset = verticalOffset;
	self.needsDisplay = YES;
	self.needsLayoutLabels = YES;
}


- (void)setDefaultRange:(BaseRange)defaultRange {
	if(defaultRange.start < 0) {
		defaultRange.start = 0;
	} else if(defaultRange.start > MAX_TRACE_LENGTH-2) {
		defaultRange.start = MAX_TRACE_LENGTH-2;
	}
	if(defaultRange.len < 2) {
		defaultRange.len = 2;
	} else if(defaultRange.start + defaultRange.len > MAX_TRACE_LENGTH) {
		defaultRange.len = MAX_TRACE_LENGTH - defaultRange.start;
	}
	_defaultRange = defaultRange;
	[self updateViewLength];
	[self fitToIntrinsicContentSize];
}



#pragma mark - reacting to mouse and key events

- (BOOL)acceptsFirstResponder {
	return YES;
}


- (BOOL)resignFirstResponder {
	self.rulerView.currentPosition = -10000;
	for (ViewLabel *label in self.viewLabels){
		label.highlighted = NO;
	}
	self.spaceDown = NO;
	return YES;
}


- (BOOL)acceptsFirstMouse:(NSEvent *)event{
	return YES;
}


- (void)updateCursor {
	if(hoveredBinLabel.hoveredEdge || hoveredMarkerLabel.hoveredEdge) {
		[NSCursor.resizeLeftRightCursor set];
		dashedLineLayer.hidden = YES;
	} else if(hoveredBinLabel == nil && hoveredMarkerLabel) {
		if(!hoveredMarkerLabel.highlighted) {
			/// if the marker label is enabled and not highlighted, we can add bins manually to it.
			[NSCursor.dragCopyCursor set];
		} else {
			if(hoveredMarkerLabel.clicked) {
				/// otherwise, the label can be dragged.
				[NSCursor.closedHandCursor set];
			} else {
				[NSCursor.openHandCursor set];
			}
		}
		dashedLineLayer.hidden = NO;
	} else {
		[NSCursor.arrowCursor set];
		dashedLineLayer.hidden = YES;
	}
}


- (void)mouseMoved:(NSEvent *)theEvent {
	if(mouseIn) {
		self.mouseLocation = [self convertPoint:theEvent.locationInWindow fromView:nil];
	}
}


- (void)setMouseLocation:(NSPoint)location {
	_mouseLocation = location;
	mouseIn = (NSPointInRect(location, self.visibleRect));
	/// we make the ruler view indicates the current position of the cursor, in base pairs
	if(mouseIn) {
		self.rulerView.currentPosition = [self sizeForX:_mouseLocation.x];
		/// if the mouse is within a marker label (which means it is editable), we position the vertical dashed line that helps the user add a bin.
		if(self.enabledMarkerLabel && dashedLineLayer) {
			dashedLineLayer.position = CGPointMake(_mouseLocation.x, 0);
		}
	}
}


- ( void)mouseExited:(NSEvent *)event {
	dashedLineLayer.hidden = YES;
	[super mouseExited:event];
	self.rulerView.currentPosition = -10000;		/// this removes the display of the current cursor position from the ruler view
}


static BOOL pressure = NO; /// to react only upon force click and not after

- (void)pressureChangeWithEvent:(NSEvent *)event {
	/// upon force click, we either select a bin (to edit it) or create a peak that could be missing at the location
	if(!pressure && event.stage >= 2.0) {
		pressure = YES;
		NSPoint mouseLocation = [self convertPoint:event.locationInWindow fromView:nil];
		if(NSPointInRect(mouseLocation, self.enabledMarkerLabel.frame)) {
			Mmarker *marker = self.enabledMarkerLabel.region;
			if(marker.editState != editStateBinSet) {
				/// If the click is within the enabled marker label, the user may already be editing individual bins
				/// in which case a force click isn't need. Or they may be editing the marker offset, in which case no bin should not be selectable
				/// We only allow to proceed if the user is moving the bin set, which pertains to bin editing. 
				return;
			}
		}
		for(FragmentLabel *fragmentLabel in self.fragmentLabels) {
			/// If the click happens to be in a fragment label, we do nothing. Selecting a bin behind it would look strange.
			if(NSPointInRect(mouseLocation, fragmentLabel.frame)) {
				return;
			}
		}
		for(RegionLabel *binLabel in self.binLabels) {
			if(!binLabel.hidden && NSPointInRect(mouseLocation, binLabel.frame)) {
				Mmarker *marker = ((Bin *)binLabel.region).marker;
				marker.editState = editStateBins;
				binLabel.highlighted = YES;
				return;
			}
		}
		
		if(self.loadedTraces.count == 1) {
			int scan = [self scanForX:mouseLocation.x];
			Peak addedPeak = [self.trace missingPeakForScan:scan useRawData:self.showRawData];
			if(addedPeak.startScan > 0 && [self.trace insertPeak:addedPeak]) {
				[self finishAddPeak];
			}
		}
		
	} else if(event.stage < 2.0) {
		pressure = NO;
	}
}


- (NSMenu *)menuForEvent:(NSEvent *)event {
	NSMenu *menu = [super menuForEvent:event];
	if(menu) {
		return menu;
	}
	if(self.loadedTraces.count == 1 && !self.enabledMarkerLabel && ![self.activeLabel isKindOfClass:PeakLabel.class]) {
		/// if  there was no peak label at the clicked point, we present the option to add a peak at the mouse location
		/// but we first check if the clicked region corresponds to a peak
		int clickedScan = [self scanForX:self.rightClickedPoint.x];
		NSPoint point = [self pointForScan:clickedScan];
		if(point.y < self.rightClickedPoint.y) {
			/// if the clicked point is not below the curve, we do nothing.
			return nil;
		}
		Peak addedPeak = [self.trace missingPeakForScan:clickedScan useRawData:self.showRawData];
		if(addedPeak.startScan > 0) {					/// this would be 0 if there there is no peak
			if(!addPeakMenu) {
				addPeakMenu = NSMenu.new;
				NSMenuItem *item = [[NSMenuItem alloc]initWithTitle:@"Add Peak here"
															 action:@selector(addPeak:)
													  keyEquivalent:@""];
				[addPeakMenu addItem:item];
			}
			/// We add the peak to menu item.
			NSMenuItem *item = addPeakMenu.itemArray.lastObject;
			item.representedObject = [NSValue valueWithBytes:&addedPeak objCType:@encode(Peak)];
			item.target = self;
			return addPeakMenu;
		}
	}
	return nil;
}


- (void)addPeak:(NSMenuItem *)sender {
	NSValue *peakValue = sender.representedObject;
	if(![peakValue isKindOfClass:NSValue.class]) {
		return;
	}
	Peak addedPeak;
	[peakValue getValue:&addedPeak];
	
	if([self.trace insertPeak:addedPeak]) {
		[self finishAddPeak];
	}
}


-(void)finishAddPeak {
	[self.window.undoManager setActionName:@"Add Peak"];
	/// we reposition labels immediately as we click the inserted one
	[self repositionLabels:self.peakLabels];
	for(PeakLabel *peakLabel in self.peakLabels) {
		[peakLabel updateTrackingArea];
		[peakLabel mouseDownInView];
	}
}


- (void)setSpaceDown:(BOOL)down {
	if(_spaceDown != down) {
		_spaceDown = down;
		if(down) {
			for (NSTrackingArea *area  in self.trackingAreas) {
				if(area != trackingArea) [self removeTrackingArea:area];
			}
		} else {
			[self updateTrackingAreas];
		}
	}
}

/*
 - (void)keyDown:(NSEvent *)event {  // the view can be scrolled by dragging the mouse with the space key down.
 if (event.keyCode == 49 && !spaceDown) {
 [NSCursor.openHandCursor push];
 self.spaceDown = YES;
 }
 //	[super keyDown:event];
 }
 
 
 - (void)keyUp:(NSEvent *)event {
 if (event.keyCode == 49 && !isDragging) {
 [NSCursor.currentCursor pop];
 //  [[NSCursor arrowCursor]push];
 }
 self.spaceDown = NO;
 [super keyUp:event];
 }
 
 
 
 */



- (void)deleteBackward:(id)sender {
	[self.activeLabel deleteAction:sender];
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(menuItem.action == @selector(deleteBackward:)) {
		NSString *title = self.activeLabel.deleteActionTitle;
		if(title) {
			menuItem.title = title;
			menuItem.hidden = NO;				/// because the delete menu is hidden by default
			return YES;
		}
		return NO;
	}
	return YES;
}


- (void)mouseDown:(NSEvent *)theEvent   {
	[self.window makeFirstResponder:self];
	self.mouseLocation= [self convertPoint:theEvent.locationInWindow fromView:nil];
	if (!self.spaceDown) {
		[super mouseDown:theEvent];
	} else {
		[NSCursor.closedHandCursor push];
	}
	
}  


- (void)cancelOperation:(id)sender {
	[self.activeLabel cancelOperation:sender];
	[self.enabledMarkerLabel cancelOperation:sender];
	
}

- (void)mouseDragged:(NSEvent *)theEvent   {
	/// used to let the user resize labels of add a new bin
	
	self.mouseLocation = [self convertPoint:theEvent.locationInWindow fromView:nil];
	
	if(!draggedLabel && self.activeLabel.clicked) {
		draggedLabel = self.activeLabel;
	}
	
	if(draggedLabel) {
		[draggedLabel drag];
		if(draggedLabel.dragged) {
			[self autoscrollWithDraggedLabel:draggedLabel];
		}
		return;
	}
	
	RegionLabel *enabledMarkerLabel = self.enabledMarkerLabel;
	
	if(NSPointInRect(self.clickedPoint, enabledMarkerLabel.frame) && NSPointInRect(self.mouseLocation, enabledMarkerLabel.frame)) {
		if(enabledMarkerLabel.highlighted) {
			[enabledMarkerLabel drag];
			return;
		}
		
		/// if the mouse is dragged in a unlocked marker label, the user may be trying to add a bin
		/// a the bin can be added in the region covered by the unlocked marker label, but it must not overlap an existing bin label
		if(fabs(self.clickedPoint.x - self.mouseLocation.x) > 3 && hoveredBinLabel == nil) {
			
			/// the rest is similar to the addition of new marker (see equivalent method in MarkerView.m)
			Mmarker *marker = (Mmarker*)self.enabledMarkerLabel.region;
			if(!marker.managedObjectContext) {
				return;
			}
			
			float position = [self sizeForX:self.mouseLocation.x];         			/// we convert the mouse position in base pairs
			float clickedPosition =  [self sizeForX:self.clickedPoint.x];      		/// we obtain the original clicked position in base pairs
			
			/// we check if we have room to add the new bin
			float safePosition = position < clickedPosition? clickedPosition - 0.13 : clickedPosition + 0.13;
			for(Bin *bin in marker.bins) {
				if(safePosition >= bin.start && safePosition <= bin.end) {
					return;
				}
			}
			
			
			dashedLineLayer.hidden = YES;											/// it is better to hide the dashed line when the bin is created, to reduce visual clutter.
			MarkerOffset offset = enabledMarkerLabel.offset;
			position = (position - offset.intercept) / offset.slope;
			clickedPosition = (clickedPosition - offset.intercept) / offset.slope;
			
			float start = (position < clickedPosition) ? position:clickedPosition;	/// we determine the start of the bin, depending on the direction of the drag
			float end = (position < clickedPosition) ? clickedPosition:position;
			
			
			if(marker.objectID.isTemporaryID) {
				[marker.managedObjectContext obtainPermanentIDsForObjects:@[marker] error:nil];
			}
			temporaryContext =[[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
			temporaryContext.parentContext = marker.managedObjectContext;
			marker = [temporaryContext existingObjectWithID:marker.objectID error:nil];
			
			if(marker.managedObjectContext != temporaryContext) {
				NSError *error = [NSError errorWithDescription:@"The bin could not be added because an error occurred in the database." suggestion:@"You may quit the application and try again"];
				[[NSAlert alertWithError:error] beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
				}];
				return;
			}
			
			Bin *newRegion = [[Bin alloc] initWithStart:start end:end marker:marker];
			if(!newRegion) {
				return;
			}
			newRegion.name = @" ";
			RegionLabel *label = [enabledMarkerLabel addLabelForBin:newRegion];
			if(label) {
				self.binLabels = [self.binLabels arrayByAddingObject:label];
				draggedLabel = label;
				label.highlighted = YES;            /// we highlight the label and the correct edge to allow immediate sizing (see above)
				label.clicked = YES;
				label.clickedEdge = position < clickedPosition? leftEdge: rightEdge;
				[NSCursor.resizeLeftRightCursor set];
			}
			return;
		}
	}
	
	if (self.spaceDown | isDragging) {       /// if the space key is pressed, dragging the mouse scrolls the view.
		isDragging = YES;
		
		float newOrigin = self.visibleOrigin + startPoint - self.mouseLocation.x;
		if(newOrigin < 0) newOrigin = 0;
		else if(newOrigin > self.bounds.size.width - self.visibleRect.size.width)
			newOrigin = self.bounds.size.width - self.visibleRect.size.width;
		
		[self.enclosingScrollView scrollClipView:(NSClipView*)self.superview toPoint:NSMakePoint(newOrigin, 0)];
		
		
		return;
	}
}


- (void)autoscrollWithDraggedLabel:(ViewLabel *)draggedLabel {
	/// we autoscroll if the mouse is dragged over the rightmost button on the left (the "+"' button), or the button on the right
	if(!NSPointInRect(self.mouseLocation, draggedLabel.frame)) {
		return;
	}
	
	float location = self.mouseLocation.x;
	NSRect rect = self.visibleRect;
	float leftLimit = rect.origin.x;
	float rightLimit = NSMaxX(rect);
	
	/// if the mouse goes beyond the left limit, we scroll to the right, hence reveal the left
	float delta = location - leftLimit;
	if(delta < 0) {
		if(self.visibleOrigin + delta >= 0) {
			NSPoint scrollPoint = NSMakePoint(self.visibleOrigin+delta, 0);
			[self.enclosingScrollView scrollClipView:(NSClipView *)self.superview toPoint:scrollPoint];
		}
		return;
	}
	
	/// if the mouse goes beyond the right limit, we scroll to the opposite direction
	delta = location - rightLimit;
	if(delta > 0) {
		float newOrigin = self.visibleOrigin + delta;
		if(newOrigin + self.visibleRect.size.width <= NSMaxX(self.bounds)) {
			NSPoint scrollPoint = NSMakePoint(newOrigin, 0);
			[self.enclosingScrollView scrollClipView:(NSClipView *)self.superview toPoint:scrollPoint];
		}
	}
}


- (void)updateTrackingAreas {
	self.isMoving = YES;
	/// For performance, we avoid updating tracking areas too frequently, in particular during scrolling or zooming.
	/// In particular since macOS 13, this method is called at every step during scrolling
	/// But we need a timer to update the tracking areas when scrolling/zooming if finished
	if(resizingTimer.valid) {
		[resizingTimer invalidate];
	}
	resizingTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(doneMoving) userInfo:nil repeats:NO];
	[[NSRunLoop mainRunLoop] addTimer:resizingTimer forMode:NSRunLoopCommonModes];
}


- (void)doneMoving {
	self.isMoving = NO;
	if(self.autoScaleToHighestPeak) {
		[self scaleToHighestPeakWithAnimation:YES];
	}
	[self _updateTrackingAreas];
}


- (void)_updateTrackingAreas {
	[super updateTrackingAreas];  			  /// this updates the view's main tracking area, which occupies the visible rect
	
	[self updateLabelAreas];
	
	if(self.markerView && !_markerView.hidden) {
		[_markerView updateTrackingAreas];
	}
}
	
	
-(void)updateLabelAreas {
	if (self.enabledMarkerLabel) {
		[self.enabledMarkerLabel updateTrackingArea];
		[self updateTrackingAreasOf:self.enabledMarkerLabel.binLabels];
	} else {
		[self updateTrackingAreasOf:self.peakLabels];
	}
}



# pragma mark - others

- (void)dealloc {
	[self stopObservingSamples];
	[NSUserDefaults.standardUserDefaults removeObserver:self forKeyPath:OutlinePeaks];
}


@end
