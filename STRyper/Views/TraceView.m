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
#import "VScaleView.h"
#import "Mmarker.h"
#import "Allele.h"
#import "Bin.h"
#import "PeakLabel.h"
#import "MarkerView.h"
#import "RulerView.h"
#import "Genotype.h"
#include <sys/sysctl.h>

@interface TraceView ()

/// redefinition of properties that are readonly in the header
@property (nonatomic) ChannelNumber channel;
@property (nonatomic, weak, nullable) Trace *trace;
@property (nonatomic, nullable) NSArray *peakLabels;
@property (nonatomic, nullable) NSArray *fragmentLabels;

/// The trace that has been clicked, if any.
@property (nonatomic, weak, nullable) Trace *clickedTrace;


/// the label of the marker whose offset or bins are being edited.
@property (nonatomic, weak, nullable) RegionLabel *enabledMarkerLabel;
																		
/// Used to animate a change in visibleRange. We use NSSize rather than BaseRange because the animator doesn't recognize the BaseRange struct.
@property (nonatomic) NSSize animatableRange;

/// Whether the traces should be redrawn (upon geometry change of change of other attributes).
@property (nonatomic) BOOL needsDisplayTraces;

/// The rectangle that is clipped by our superview (in our coordinates), subtracting the region masked by the vscale view.
@property (readonly, nonatomic) NSRect clipRect;

/// The width of the `clipRect` (faster to generate)
@property (readonly, nonatomic) float visibleWidth;

/// Colors used for offscale regions, ordered from channel 0 to channel 4.
@property (nonatomic, readonly) NSArray<NSColor *> *colorsForOffScaleRegions;

@end

/// pointers giving context to KVO notifications
static void * const sampleSizingChangedContext = (void*)&sampleSizingChangedContext;
static void * const samplePanelChangedContext = (void*)&samplePanelChangedContext;
static void * const endSizeChangedContext = (void*)&endSizeChangedContext;
static void * const peakChangedContext = (void*)&peakChangedContext;
static void * const fragmentsChangedContext = (void*)&fragmentsChangedContext;
static void * const panelMarkersChangedContext = (void*)&panelMarkersChangedContext;


/// We give values to the binding names
NSBindingName const ShowOffScaleRegionsBinding = @"showOffscaleRegions",
ShowPeakTooltipsBinding = @"showPeakTooltips",
PaintCrosstalkPeakBinding = @"paintCrosstalkPeaks",
ShowBinsBinding = @"showDisabledBins",
ShowRawDataBinding = @"showRawData",
MaintainPeakHeightsBinding = @"maintainPeakHeights",
AutoScaleToHighestPeakBinding = @"autoScaleToHighestPeak",
DisplayedChannelsBinding = @"displayedChannels",
IgnoreCrossTalkPeaksBinding = @"ignoreCrosstalkPeaks",
DefaultRangeBinding = @"defaultRange";

/// some variables shared by all instances
static NSArray *animatableKeys;		/// Keys that are animatable.

static const float maxHScale = 500.0; 	/// the maximum hScale (pts per base pair), to avoid making the view too wide.

static const int threshold = 1;   	/// height (in points) below which we do not add points to the fluorescence curve and just draw a straight line (optimization)


static BOOL appleSilicon;			/// whether the Mac running the application has an Apple SoC.
									/// We use it for drawing optimisations.

@implementation TraceView {
	
	float viewHeight;					/// a shortcut to the view's height, to avoid recomputing it.
	float viewLength;				/// the horizontal length of the view in base pairs
	
	NSTimer *updateTrackingAreasTimer;			/// A timer that triggers to update tracking areas, and avoid updating them when the view is moving or resized
	
	CAShapeLayer *dashedLineLayer;	/// a layer showing a vertical dashed line at the mouse location that helps the user insert bins
									/// (note: we could use a single instance in a global variable for this layer, since only one dashed line should show at a time)
	
	CALayer *verticalLineLayer;		/// A vertical line at the location of peaks that are hovered by the mouse.
	
	NSArray<Trace *> *visibleTraces;		/// the traces that are actually visible, depending on the channel to show
	
	NSArray *observedSamples;				/// The chromatograms observed for certain keypaths.
	
	__weak RegionLabel *hoveredBinLabel;	/// the bin label being hovered, which we use to determine the cursor
	__weak PeakLabel *hoveredPeakLabel;		/// the peak label being hovered, which we may need to reposition
	
	BOOL showMarkerOnly;
	
	/**** ivars used for drawing traces **/
	/// We don't draw traces in the backing layer as we need to show bin and marker labels (which use layers) behind traces.
	/// A single layer cannot hold the whole traces. If it's too large, drawing is slow or doesn't work (even if constrained to a small rectangle of the layer).
	/// A CATiledLayer can be very large, but doesn't appear suited to this task.
	/// We instead position and draw contiguous layers during scrolling (similar to "responsive scrolling).
	
	BOOL showsTraces; 			/// A shortcut to indicate whether the view shows traces.
	CALayer *traceLayerParent; 		/// The parent layer of the trace layers, sorted from left to right along the X axis in its sublayers array
	__weak CALayer *traceLayerFillingClipRect;		/// The trace layer that fits in the `clipRect`, if any.
													/// We use this information to avoid repositioning this layer when not required
	
	NSMutableSet<CALayer *> *traceLayers; /// The currently unused layers that are not in the layer tree.
	
	float drawnRangeStart;		/// The position of the leading edge of the leftmost trace layer (in view coordinates), which we store to avoid computations
	float drawnRangeEnd;		/// The position of the trailing edge of the rightmost trace layer
	
	NSMutableSet *fragmentLabelsToReposition; /// Used to determine wether we should reposition Fragment labels during -layout.
		
	BOOL needsUpdateAppearance; /// To determine whether we need to update colors (background layer, others) to adapt to the current appearance.
								/// This ivar avoid doing these changes during updateLayer when not necessary
								/// (as the method is also called to update label colors, which is required more often).
	
	/// ivars used to denote if view labels needs to be updated, and to avoid redundant updates in the same cycle.
	BOOL needsUpdateFragmentLabels;
	BOOL needsUpdateMarkerLabels;
	BOOL needsUpdatePeakLabels;
	
	BOOL needsLayoutTraceLayer;
}

static const float defaultTraceLayerWidth = 512; /// Default width of a trace layer in points

@synthesize markerLabels = _markerLabels, backgroundLayer = _backgroundLayer, rulerView = _rulerView, markerView = _markerView, colorsForOffScaleRegions = _colorsForOffScaleRegions, fragmentLabelBackgroundColor = _fragmentLabelBackgroundColor, alleleLabelBackgroundColor = _alleleLabelBackgroundColor, fragmentLabelStringColor = _fragmentLabelStringColor, binLabelColor = _binLabelColor, hoveredBinLabelColor = _hoveredBinLabelColor, regionLabelEdgeColor = _regionLabelEdgeColor, binNameBackgroundColor = _binNameBackgroundColor, hoveredBinNameBackgroundColor = _hoveredBinNameBackgroundColor, traceViewMarkerLabelBackgroundColor = _traceViewMarkerLabelBackgroundColor, traceViewMarkerLabelAllowedRangeColor = _traceViewMarkerLabelAllowedRangeColor, isResizing = _isResizing;

#pragma mark - initialization methods

static NSColor *traceViewBackgroundColor;

+ (void)initialize {
	if (self == TraceView.class) {
		animatableKeys = @[NSStringFromSelector(@selector(topFluoLevel)),
						   NSStringFromSelector(@selector(animatableRange)),
						   NSStringFromSelector(@selector(vScale))];
		
		/// We determine if the SoC is from Apple by reading the CPU brand.
		/// There may be a better way by reading the architecture.
		size_t size = 100;		/// To make sure that we can read the whole CPU name.
		char string[size];
		sysctlbyname("machdep.cpu.brand_string", &string, &size, nil, 0);
		appleSilicon = strncmp(string, "Apple", 5) == 0;
		
		traceViewBackgroundColor = [NSColor colorNamed: @"traceViewBackgroundColor"];
	}
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
	
	traceLayers = NSMutableSet.new;
	traceLayerParent = CALayer.new;
	traceLayerParent.delegate = self;
	traceLayerParent.zPosition = -0.4;  /// To ensure traces show behind fragment labels, which cannot have a positive zPosition.
	traceLayerParent.anchorPoint = CGPointMake(0, 0);
	traceLayerParent.position = CGPointMake(0, 0);
	[self.layer addSublayer:traceLayerParent];
	
	self.layer.opaque = YES;
	
	/// we update what the view shows "manually".
	self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
	
	[self setBoundsOrigin:NSMakePoint(0, -0.5)];
	
	/// we initialize the layer showing the dashed line that show at the mouse location over the enabled marker label
	dashedLineLayer = CAShapeLayer.new;
	dashedLineLayer.anchorPoint = CGPointMake(1, 0); /// this will position the layer at the left of the mouse location, which place it more in line with the cursor
	dashedLineLayer.fillColor = NSColor.clearColor.CGColor;
	dashedLineLayer.strokeColor = NSColor.textColor.CGColor;
	dashedLineLayer.lineWidth = 1.0;
	dashedLineLayer.lineDashPattern = @[@(1.0), @(2.0)];
	dashedLineLayer.delegate = self;
	[self.layer addSublayer:dashedLineLayer];
	
	/// The layer denoting the hovered peak label
	verticalLineLayer = CALayer.new;
	verticalLineLayer.opaque = YES;
	verticalLineLayer.delegate = self;
	verticalLineLayer.zPosition = -0.3; /// so that it doesn't show above fragment labels
	[self.layer addSublayer:verticalLineLayer];
	
	_showDisabledBins = YES;
	_showRawData = NO;
	_showOffscaleRegions = YES;
	_paintCrosstalkPeaks = YES;
	_defaultRange = MakeBaseRange(0, 500);
	_hScale = -1.0;  /// we avoid 0 as some methods divide numbers by this ivar
	_channel = noChannelNumber;
	
	/************************observations to update view labels **************/
	///labels must be updated when peaks, fragments of the trace we show change, as well as markers
	[self addObserver:self forKeyPath:@"trace.peaks" options:NSKeyValueObservingOptionNew context:peakChangedContext];
	[self addObserver:self forKeyPath:@"trace.fragments" options:NSKeyValueObservingOptionNew context:fragmentsChangedContext];
	[self addObserver:self forKeyPath:@"panel.markers" options:NSKeyValueObservingOptionNew context:panelMarkersChangedContext];
	
	fragmentLabelsToReposition = NSMutableSet.new;
	needsUpdateAppearance = YES; /// Sets the correct colors according to the theme when the view is first shown.
	self.needsUpdateLabelAppearance = YES;
}


- (CALayer *)backgroundLayer {
	if(!_backgroundLayer) {
		_backgroundLayer = self.layer;
		_backgroundLayer.masksToBounds = NO;  /// This avoid clipping the content during resizing with animation,
											  /// as we don't animate anything with this layer (see `actionForLayer:forKey:`)
	}
	return _backgroundLayer;
}


- (BOOL)preservesContentDuringLiveResize {
	return YES;
}


- (NSInteger)tag {
	return 1;
}


- (RulerView *)rulerView {
	if(!_rulerView) {
		NSScrollView *scrollView = self.enclosingScrollView;
		if(scrollView && scrollView.documentView == self) {
			scrollView.rulersVisible = YES;
			RulerView *rulerView = RulerView.new;
			scrollView.horizontalRulerView = rulerView;
			rulerView.ruleThickness = ruleThickness;
			rulerView.reservedThicknessForMarkers = 0.0;
			rulerView.reservedThicknessForAccessoryView = markerViewHeight;
			rulerView.clientView = self;
			NSPoint boundsOrigin = self.bounds.origin;
			[_rulerView setBoundsOrigin:NSMakePoint(boundsOrigin.x, 0)];
			_rulerView = rulerView;
		}
	}
	return _rulerView;
}


- (MarkerView *)markerView {
	if(!_markerView && self.rulerView) {
		_markerView = MarkerView.new;
		self.rulerView.accessoryView = _markerView;
		NSPoint boundsOrigin = self.bounds.origin;
		[_markerView setBoundsOrigin:NSMakePoint(boundsOrigin.x, 0)];
		[_markerView setFrameSize:NSMakeSize(_markerView.frame.size.width, markerViewHeight)];
	}
	return(_markerView);
}



#pragma mark - loading content


- (void)loadContent:(id)object {
	_genotype = nil;
	if([object isKindOfClass:NSArray.class]) {
		NSArray *traces = object;
		if([traces.firstObject isKindOfClass:Trace.class]) {
			[self loadTraces:object marker:nil];
		}
	} else if([object isKindOfClass:Trace.class]) {
		[self loadTraces:@[object] marker:nil];
	}
	else if([object isKindOfClass:Genotype.class]) {
		Genotype *genotype = object;
		Trace *trace = [genotype.sample traceForChannel:genotype.marker.channel];
		if(trace) {
			_genotype = genotype;
			[self loadTraces:@[trace] marker:genotype.marker];
		} else {
			[self loadTraces:nil marker:nil];
		}
	} else if ([object isKindOfClass:Chromatogram.class]) {
		Chromatogram *sample = object;
		[self loadTraces:sample.traces.allObjects marker:nil];
	} else if([object isKindOfClass:Mmarker.class]) {
		[self loadTraces:nil marker:object];
	} else {
		[self loadTraces:nil marker:nil];
	}
}

/// loads the specified traces and marker
- (void)loadTraces:(nullable NSArray<Trace *> *)traces marker:(nullable Mmarker *)marker {
	
	/// We set the hScale to -1 to signify that our geometry is reset and not final.
	_hScale = -1.0;
	if(updateTrackingAreasTimer.valid) {
		[updateTrackingAreasTimer invalidate];
	}
	
	_marker = marker;
			
	/// We determine the channel that we show.
	/// We record our previous channel to determine if we should load the panel or keep the previous one, as we only show markers associated with a single channel.
	ChannelNumber previousChannel = self.channel;
	if(marker) {
		self.channel = marker.channel;
	}
	
	self.loadedTraces = traces;
	NSInteger traceCount = traces.count;

	/// We set the panel of markers (even in case we show a single marker, we need to load others as marker resizing depends on other markers of the same channel)
	Panel *refPanel = self.panelToShow;
	
	/// we check if we should set the new panel. We may not if it is the same as before and if the channel hasn't changed
	/// this increases performance when switching between samples while the user scrolls (avoids hitches)
	/// but if we don't or didn't show a trace (hence only a marker), we always load the panel.
	/// this because the marker we highlight may be different (even if from the same panel and channel) and the way we show the panel also depends on whether we show traces
	if(showMarkerOnly || traceCount == 0 || previousChannel != self.channel || self.panel != refPanel || refPanel == nil) {
		self.panel = refPanel;
	}
	
	[self getRangeAndScale];
	self.needsRepositionLabels = YES; /// Probably redundant.
	
	showMarkerOnly = traceCount == 0;
}

/// Returns the panel of markers that we (and our marker view) may show.
///
/// We show a panel if only one channel is shown and if traces don't correspond to samples having different panels.
/// We don't show the panel if samples are not sized (no size standard, sizing failed...)
-(nullable Panel *)panelToShow {
	if(self.channel < 0 || self.trace.isLadder) {
		return nil;
	}
	
	if(self.marker.panel && self.loadedTraces.count == 0) {
		return self.marker.panel;
	}
	
	Panel *refPanel = nil;
	for(Trace *trace in visibleTraces) {
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


- (void)setChannel:(ChannelNumber)channel {
	if(_channel != channel) {
		_channel = channel;
		[self updateAlleleLabelBackgroundColor] ;
	}
}


- (void)setLoadedTraces:(NSArray <Trace *>*)traces {
	/// as we observe some properties of samples, we must stop observing previous samples
	[self stopObservingSamples];
	
	NSUInteger traceCount = traces.count;
	if(traceCount > 400) {
		traces = [traces objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 400)]];
	}
	_loadedTraces = traces;
	visibleTraces = traces;
	showsTraces = traceCount > 0;

	Trace *referenceTrace; /// The trace that will become self.trace.
	
	if(showsTraces) {
		Trace *firstTrace = traces.firstObject;
		BOOL stackedChannels = traceCount > 1 && firstTrace.channel != traces.lastObject.channel;
		BOOL oneSample = stackedChannels || traceCount == 1; /// We assume that traces from different channels are from the same chromatogram.
		
		if(stackedChannels) {
			visibleTraces = [traces filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Trace *trace, NSDictionary<NSString *,id> * _Nullable bindings) {
				return [self.displayedChannels containsObject: @(trace.channel)];
			}]];
		}
		
		NSInteger visibleTraceCount = visibleTraces.count;
		referenceTrace = visibleTraceCount > 0? visibleTraces.firstObject : firstTrace;
		self.channel = visibleTraceCount == 0? noChannelNumber :
		(visibleTraceCount > 1 && stackedChannels? multipleChannelNumber : referenceTrace.channel);
		
		float maxReadLength = -1; /// Used to pick self.trace in case the view shows several samples.
		for (Trace *trace in traces) {
			Chromatogram *sample = trace.chromatogram;
			if (sample.readLength > maxReadLength && sample.sizingQuality) {
				maxReadLength = sample.readLength; /// This call potentially updates the sample's `sizes` attribute, which is useful to do now
												   /// before the sample is observed, to avoid sending unnecessary notification to the view
				if(!oneSample) {
					referenceTrace = trace;
				}
			}
			[sample addObserver:self forKeyPath:ChromatogramCoefsKey options:NSKeyValueObservingOptionNew context:sampleSizingChangedContext];
			[sample addObserver:self forKeyPath:ChromatogramSizingQualityKey options:NSKeyValueObservingOptionNew context:sampleSizingChangedContext];
			[sample addObserver:self forKeyPath:ChromatogramPanelKey options:NSKeyValueObservingOptionNew context:samplePanelChangedContext];
			if(oneSample) {
				observedSamples = @[firstTrace.chromatogram];
				break;
			}
		}
		
		if(!oneSample) {
			/// The instruction below is much faster than incrementing an array.
			observedSamples = [traces valueForKeyPath:@"@unionOfObjects.chromatogram"];
		}
	}

	self.trace = referenceTrace; /// This updates fragment and peak labels via KVO.
	traceLayerParent.hidden = !showsTraces;
	if(showsTraces) {
		self.needsDisplayTraces = YES;
	}
	[self updateViewLength];
	self.markerView.hidden = self.channel == multipleChannelNumber || (referenceTrace.isLadder && visibleTraces.count > 0);
}


-(void)stopObservingSamples {
	for(Chromatogram *sample in observedSamples) {
		[sample removeObserver:self forKeyPath:ChromatogramCoefsKey];
		[sample removeObserver:self forKeyPath:ChromatogramSizingQualityKey];
		[sample removeObserver:self forKeyPath:ChromatogramPanelKey];
	}
	observedSamples = nil;
}


- (void)prepareForReuse {
	[super prepareForReuse]; /// probably not needed but Apple says we should.
	[self stopObservingSamples];
	_loadedTraces = nil;	/// We don't use the setter to avoid calling setTrace:, which triggers KVO notifications with unwanted side effects
							/// since the view is not used at this point (removing labels, hiding the vScaleView, etc.)
	if(updateTrackingAreasTimer.valid) {
		[updateTrackingAreasTimer invalidate];
	}
	visibleTraces = nil;
	showsTraces = NO;
	self.clickedTrace = nil;
	_marker = nil;
	_genotype = nil;
	_hScale = -1;
	/// We don't set the panel to nil as we may reuse marker labels.
}

#pragma mark - managing labels


-(void)setPanel:(Panel *)panel {
	_panel = panel;
}


- (void)updateMarkerLabels {
	NSArray *markers = [self.panel markersForChannel:self.channel];
	NSArray *markerLabels = [self regionLabelsForRegions:markers reuseLabels:self.markerLabels];
	
	if(markers.count > 0) {
		self.needsRepositionLabels = YES;
	}
	self.markerLabels = markerLabels;
	needsUpdateMarkerLabels = NO;
}


-(void)setMarkerLabels:(NSArray *)markerLabels {
	for(RegionLabel *label in _markerLabels) {
		if([markerLabels indexOfObjectIdenticalTo:label] == NSNotFound) {
			[label removeFromView];
		}
	}
	_markerLabels = markerLabels;
	[self.markerView updateContent];
}


- (void)updateLayer {
	if(needsUpdateMarkerLabels) {
		[self updateMarkerLabels];
	}
	
	if(needsUpdateFragmentLabels) {
		[self updateFragmentLabels];
	}
	
	if(needsUpdatePeakLabels) {
		[self updatePeakLabels];
	}
	
	NSArray *fragmentLabels = self.fragmentLabels;
	BOOL needsRepositionLabels = self.needsRepositionLabels;
	/// We consider fragments to reposition separately to force animations on their repositioning.
	/// These should be fragments that had their position changed "manually", otherwise `_needsRepositionFragmentLabels` would be `YES`.
	BOOL fragmentLabelsToRepositionSeparately = fragmentLabelsToReposition.count > 0 && !_needsRepositionFragmentLabels &&
	!(needsRepositionLabels && !self.trace.isLadder);
	if(fragmentLabelsToRepositionSeparately) {
		fragmentLabels = [fragmentLabels arrayByRemovingObjectsInArray:fragmentLabelsToReposition.allObjects];
	}
	
	NSInteger fragmentLabelCount = fragmentLabels.count;
	if(fragmentLabelCount > 0 &&
	   (_needsRepositionFragmentLabels || needsRepositionLabels) && self.hScale >=0) {
		for(FragmentLabel *label in fragmentLabels) {
			[label reposition];
		}
		if(fragmentLabelCount > 1 && !fragmentLabelsToRepositionSeparately) {
			[FragmentLabel avoidCollisionsInView:self];
		}
	}

	[super updateLayer];
	self.needsRepositionFragmentLabels = NO;
	if(fragmentLabelsToRepositionSeparately) {
		for(FragmentLabel *label in self.fragmentLabels) {
			/// Here, repositioning should be animated, as `needsLayoutFragmentLabels` and `needsRepositionLabels` return `NO`
			/// We reposition all fragment labels to properly manage the case where a label no longer needs to avoid collisions.
			[label reposition];
		}
		[FragmentLabel avoidCollisionsInView:self];
	}
	[fragmentLabelsToReposition removeAllObjects];
	if(needsUpdateAppearance) {
		self.layer.backgroundColor = traceViewBackgroundColor.CGColor;
		self.enclosingScrollView.backgroundColor = traceViewBackgroundColor;
		dashedLineLayer.strokeColor = NSColor.textColor.CGColor;
		verticalLineLayer.backgroundColor = dashedLineLayer.strokeColor;
		
		_colorsForOffScaleRegions = nil;
		
		if(self.colorsForOffScaleRegions) {
			self.needsDisplayTraces = YES;
		}
		
		needsUpdateAppearance = NO;
	}
	
	if(self.needsUpdateLabelAppearance) {
		[self updateFragmentLabelBackgroundColor];
		[self updateFragmentLabelStringColor];
		[self updateBinLabelColor];
		[self updateHoveredBinLabelColor];
		[self updateRegionLabelEdgeColor];
		[self updateBinNameBackgroundColor];
		[self updateHoveredBinNameBackgroundColor];
		[self updateTraceViewMarkerLabelBackgroundColor];
		[self updateTraceViewMarkerLabelAllowedRangeColor];
		
		for(RegionLabel *label in self.markerLabels) {
			[label updateForTheme];
		}
		
		for(FragmentLabel *label in self.fragmentLabels) {
			[label updateForTheme];
		}
		
		self.needsUpdateLabelAppearance = NO;
	}
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
			/// We don't disable fragment labels that don't correspond to peaks in the marker.
			Allele *allele = label.fragment;
			if([allele respondsToSelector:@selector(genotype)]) {
				label.enabled = allele.genotype.marker != markerLabel.region;
			}
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
	if(visibleTraces.count == 1 || (self.showOffscaleRegions && self.channel < 0)) {
		/// We redraw as we don't show off-scale regions or crosstalk when a marker label is enabled (to avoid interference with its rectangle and its bins).
		self.needsDisplayTraces = YES;
	}
}


/// Returns fragment labels that represent trace fragments.
///
/// This method tries to reuse fragment labels to avoid creating new one, which takes longer.
/// - Parameters:
///   - fragments: The fragments that the labels should represent.
///   - fragmentLabels: The fragment labels to reuse.
-(NSArray <FragmentLabel *>*) fragmentLabelsForFragments:(NSArray <LadderFragment *>*)fragments
											 reuseLabels:(NSArray <FragmentLabel *>*) fragmentLabels {
	NSInteger fragmentCount = fragments.count;
	if(fragmentCount == 0) {
		return NSArray.new;
	}
	
	Mmarker *marker = self.enabledMarkerLabel.region;
	BOOL isLadder = self.trace.isLadder;
	if(fragmentLabels.count == 0) {
		NSMutableArray *newLabels = [NSMutableArray arrayWithCapacity:fragmentCount];
		for (LadderFragment * fragment in fragments) {
			FragmentLabel *label = [[FragmentLabel alloc] initFromFragment:fragment view:self];
			if(marker && !isLadder && ((Allele *)fragment).genotype.marker == marker) {
				label.enabled = NO;
			}
			[newLabels addObject:label];
		}
		return [NSArray arrayWithArray:newLabels];
	}
	
	NSArray *reusedAsIsLabels = self.hScale <= 0? NSArray.new :  /// If we are loading new content, the trace is most likely different so we don't try to find labels that already represent its fragments
	[fragmentLabels filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(FragmentLabel *label, NSDictionary<NSString *,id> * _Nullable bindings) {
		return [fragments indexOfObjectIdenticalTo:label.fragment] != NSNotFound;
	}]];
	
	NSInteger reusedCounts = reusedAsIsLabels.count;
	if(reusedCounts < fragmentCount) {
		NSArray *fragmentsWithLabels = [reusedAsIsLabels valueForKeyPath:@"@unionOfObjects.fragment"];
		NSArray *otherLabels;
		if(reusedCounts < fragmentLabels.count) {
			otherLabels = reusedCounts == 0? fragmentLabels : [fragmentLabels arrayByRemovingObjectsIdenticalInArray:reusedAsIsLabels];
		}
		
		NSMutableArray *newLabels = [NSMutableArray arrayWithCapacity:fragmentCount - reusedCounts];
		NSInteger reassignedLabelsCount = 0;
		NSInteger otherLabelsCount = otherLabels.count;
		BOOL cannotDisable = marker == nil || isLadder;
		for(LadderFragment *fragment in fragments) {
			BOOL enable = cannotDisable || ((Allele *)fragment).genotype.marker != marker;
			if([fragmentsWithLabels indexOfObjectIdenticalTo:fragment] == NSNotFound) {
				FragmentLabel *fragmentLabel;
				if(reassignedLabelsCount < otherLabelsCount) {
					fragmentLabel = otherLabels[reassignedLabelsCount];
					fragmentLabel.fragment = fragment;
					fragmentLabel.highlighted = NO;
					reassignedLabelsCount++;
				} else {
					fragmentLabel = [[FragmentLabel alloc]initFromFragment:fragment view:self];
				}
				fragmentLabel.enabled = enable;
				[newLabels addObject:fragmentLabel];
			}
		}
		reusedAsIsLabels = [reusedAsIsLabels arrayByAddingObjectsFromArray:newLabels];
	}
	return reusedAsIsLabels;
}


-(void)updateFragmentLabels {
	if(visibleTraces.count == 1) {
		self.fragmentLabels = [self fragmentLabelsForFragments:self.trace.fragments.allObjects reuseLabels:self.fragmentLabels];
	} else {
		self.fragmentLabels = NSArray.new;
	}
	needsUpdateFragmentLabels = NO;
}


- (void)setFragmentLabels:(NSArray *)fragmentLabels {
	for(FragmentLabel *label in _fragmentLabels) {
		if([fragmentLabels indexOfObjectIdenticalTo:label] == NSNotFound) {
			[label removeFromView];
		}
	}
	_fragmentLabels = fragmentLabels;
}


- (void)updatePeakLabels {
	NSData *peakData = self.trace.peaks;
	if(peakData && visibleTraces.count == 1) {
		NSMutableArray *temp = NSMutableArray.new;
		BOOL enable = self.enabledMarkerLabel == nil;
		const Peak *peaks = peakData.bytes;
		NSInteger nPeaks = peakData.length / sizeof(Peak);
		NSArray *peakLabels = self.peakLabels;
		NSInteger nPeakLabels = peakLabels.count;
		
		for (int i = 0; i < nPeaks; i++) {
			PeakLabel *peakLabel;
			if(i < nPeakLabels) {
				peakLabel = peakLabels[i];
				[peakLabel setPeak:peaks[i]];
			} else {
				peakLabel = [[PeakLabel alloc] initWithPeak:peaks[i] view:self];
			}
			peakLabel.enabled = enable;
			[temp addObject:peakLabel];
		}
		self.peakLabels = [NSArray arrayWithArray:temp];
	} else {
		self.peakLabels = NSArray.new;
	}
	needsUpdatePeakLabels = NO;
}


- (void)setPeakLabels:(NSArray *)peakLabels {
	for(RegionLabel *label in _peakLabels) {
		if([peakLabels indexOfObjectIdenticalTo:label] == NSNotFound) {
			[label removeFromView];
		}
	}
	_peakLabels = peakLabels;
	if(_peakLabels.count > 0 && self.hScale > 0 && !self.isMoving) {
		[self updateTrackingAreasOf:_peakLabels];
	}
	self.needsDisplayTraces = YES; /// As peaks affect the display of traces (adjusted data)
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
	} else if([label isKindOfClass:PeakLabel.class]) {
		if(label.hovered) {
			hoveredPeakLabel = (PeakLabel *)label;
		} else if(hoveredPeakLabel == label) {
			hoveredPeakLabel = nil;
		}
		[self positionVerticalLineLayer];
	}
}


- (void)labelNeedsRepositioning:(ViewLabel *)viewLabel {
	if([viewLabel isKindOfClass:FragmentLabel.class]) {
		if(!_needsRepositionFragmentLabels) {
			[fragmentLabelsToReposition addObject:viewLabel];
			self.needsDisplay = YES;
		}
	} else {
		[super labelNeedsRepositioning:viewLabel];
		RulerView *rulerView = self.rulerView;
		if(!rulerView.needsUpdateOffsets && [viewLabel respondsToSelector:@selector(isMarkerLabel)]) {
			RegionLabel *regionLabel = (RegionLabel *)viewLabel;
			if(regionLabel.isMarkerLabel) {
				rulerView.needsUpdateOffsets = YES;
			}
		}
	}
}


-(void)positionVerticalLineLayer {
	if(!hoveredPeakLabel) {
		verticalLineLayer.hidden = YES;
	} else {
		verticalLineLayer.hidden = NO;
		float tipPos = [self xForScan:hoveredPeakLabel.scan];
		verticalLineLayer.frame = CGRectMake(tipPos, 0, 1, viewHeight);
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


-(NSArray <RegionLabel *> *)binLabels {
	return [self.markerLabels valueForKeyPath:@"@unionOfArrays.binLabels"];
}


- (NSArray *) viewLabels {
	return [self.traceLabels arrayByAddingObjectsFromArray:self.panelLabels];
}


- (void)setNeedsRepositionFragmentLabels:(BOOL)needsLayoutFragmentLabels {
	_needsRepositionFragmentLabels = needsLayoutFragmentLabels;
	if(needsLayoutFragmentLabels) {
		self.needsDisplay = YES;
	}
}



-(void)layoutSublayersOfLayer:(CALayer *)layer {
	if(layer == traceLayerParent && needsLayoutTraceLayer) {
		/// As this method is called whenever the layer bounds change, we check `needsLayoutTraceLayer`
		/// to avoid doing unnecessary stuff.
		if(needsUpdatePeakLabels) {
			[self updatePeakLabels];
		}
		[self repositionTraceLayer];
		needsLayoutTraceLayer = NO;
	}
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if(context == sampleSizingChangedContext) {
		Chromatogram *sample = object;
		if(sample.coefs != nil) {
			/// We only react if the sizing properties haven't become nil (which may happen).
			if([keyPath isEqualToString:ChromatogramCoefsKey]) {
				if(sample == self.trace.chromatogram) {
					[self updateViewLength];
					[self fitToIntrinsicContentSize];
					if(_hScale > 0) {
						/// We adjust the scale and visible origin to maintain the visible range.
						self.hScale = self.visibleWidth / _visibleRange.len;
						self.visibleOrigin = (_visibleRange.start - _sampleStartSize) * _hScale;
					}
					self.needsRepositionLabels = YES;
				}
			} else if([keyPath isEqualToString:ChromatogramSizingQualityKey]){
				/// If sizing has changed, sizing may have failed for samples we show or may have become valid instead
				/// Since we don't show a panel when sizing has failed, we may need to update the panel we show
				Panel *panel = [self panelToShow];
				if(panel != self.panel) {
					self.panel = panel;
				}
			}
			self.needsDisplayTraces = YES;
			self.rulerView.needsDisplay = YES;
		}
	} else if(context == samplePanelChangedContext) {
		/// we reload the whole panel if it has changed
		Panel *panel = [self panelToShow];
		if(panel != self.panel) {
			self.panel = panel;
		}
	} else if(context == panelMarkersChangedContext) {
		needsUpdateMarkerLabels = YES;
		self.needsRepositionLabels = YES;
	} else if(context == fragmentsChangedContext) {
		needsUpdateFragmentLabels = YES;
		self.needsRepositionFragmentLabels = YES;
	} else if(context == peakChangedContext) {
		needsUpdatePeakLabels = YES;
		/// we update peak labels in layoutSubLayersOfLayer
		[self setNeedsLayoutTraceLayer];
	}
	else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	
}


# pragma mark - commands related to drawing traces

-(CALayer *)newTraceLayer {
	CALayer *traceLayer = CALayer.new;
	traceLayer.delegate = self;
	traceLayer.needsDisplayOnBoundsChange = YES;
	traceLayer.contentsScale = self.layer.contentsScale;
	traceLayer.anchorPoint = CGPointMake(0, 0);
	traceLayer.drawsAsynchronously = YES;  /// enables GPU acceleration on Apple Silicon
	return traceLayer;
}


-(void)removeTraceLayer:(CALayer *)layer {
	layer.contents = nil;
	[layer removeFromSuperlayer];
	[traceLayers addObject:layer];
}


- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	if(layer.superlayer == traceLayerParent) {
		if(_resizedWithAnimation) {
			return nil;
		}
		return NSNull.null;
	} else if(layer == traceLayerParent || layer == dashedLineLayer || layer == verticalLineLayer || layer == _backgroundLayer) {
		return NSNull.null;
	}
	return nil;
}


- (BOOL)layer:(CALayer *)layer shouldInheritContentsScale:(CGFloat)newScale fromWindow:(NSWindow *)window {
	if(layer.superlayer == traceLayerParent) {
		return YES;
	}
	return NO;
}


- (BOOL)isOpaque {
	return YES;
}


- (void)setNeedsDisplayTraces:(BOOL)display {
	if(showsTraces) {
		_needsDisplayTraces = display;
		if(display) {
			/// When traces needs to be redrawn, we draw a layer that fits the visible rectangle return by clipRect
			if(!traceLayerFillingClipRect) {
				[self setNeedsLayoutTraceLayer];
			} else {
				/// If a layer is already in place, we don't need to position it, just mark it for redisplay.
				[traceLayerFillingClipRect setNeedsDisplay];
				/// but we need to remove any other trace layer
				/* DISABLED TO TEST. This code should not be needed as traceLayerFillingClipRect is set by clearing other layers.
				NSArray *sublayers = traceLayerParent.sublayers;
				long count = sublayers.count;
				if(count > 1) {
					for (long i = 0; i < count; i++) {
						CALayer *aLayer = sublayers[i];
						if(aLayer != traceLayerFillingClipRect) {
							[self removeTraceLayer:aLayer];
							count--;
							i--;
						}
					}
				} */
			}
		}
	}
}


- (void)setNeedsLayoutTraceLayer {
	if(showsTraces) {
		needsLayoutTraceLayer = YES;
		[traceLayerParent setNeedsLayout];
	}
}


/// Resizes layers showing traces, considering the previous size of the view.
///
///  This considers that the layers grow/shrink proportionally with the view.
///  We use it when the view resizes with animation.
/// - Parameter oldSize: The size the view had before resizing.
-(void)rescaleTraceLayersWithOldSize:(NSSize)oldSize {
	NSRect bounds = self.bounds;
	NSSize size = bounds.size;
	/// This method assumes that all layers start at y = –0.5 and end at the top of the view.
	float yOffset = -bounds.origin.y - 0.5;
	if(oldSize.height - yOffset <= 0 || oldSize.width <= 0) {
		return;
	}
	float xRatio = size.width / oldSize.width;
	
	float yRatio = (size.height - yOffset) / (oldSize.height - yOffset);
	drawnRangeStart = INFINITY;
	drawnRangeEnd = 0;
	for(CALayer *traceLayer in traceLayerParent.sublayers) {
		NSRect bounds = traceLayer.bounds;
		bounds.origin.x *= xRatio;
		bounds.size.width *= xRatio;
		bounds.size.height *= yRatio;
		traceLayer.bounds = bounds;
		traceLayer.position = bounds.origin;
		
		if(drawnRangeStart > bounds.origin.x) {
			drawnRangeStart = bounds.origin.x;
		}
		if(drawnRangeEnd < NSMaxX(bounds)) {
			drawnRangeEnd = NSMaxX(bounds);
		}
	}
}


/// Positions a trace layer (or several)  to cover the visible area of the view.
-(void)repositionTraceLayer {
	NSRect clipRect = self.clipRect;
	float visibleStart = clipRect.origin.x;
	float visibleEnd = NSMaxX(clipRect);
	
	if(_needsDisplayTraces || visibleEnd < drawnRangeStart || visibleStart > drawnRangeEnd) {
		/// If traces needs to be redrawn or if the clipRect does not intersect what is drawn, we place a layer in the clipRect and remove others
		traceLayerFillingClipRect = [self positionTraceLayerFromStart:visibleStart toEnd:visibleEnd clipRect:clipRect clearOtherLayers:YES];
		return;
	}
	
	if(drawnRangeStart > 0 && visibleStart < drawnRangeStart)  {
		/// If a region that is not drawn has become visible at the left, we place a layer there.
		/// This will draw traces there.
		float layerStart = drawnRangeStart - defaultTraceLayerWidth;
		if(layerStart > visibleStart) {
			layerStart = visibleStart;
		}
		[self positionTraceLayerFromStart:layerStart toEnd:drawnRangeStart clipRect:clipRect clearOtherLayers:NO];
	}
	
	if (drawnRangeEnd < visibleEnd) {
		/// If some area has become visible at the right, we place a layer there.
		float layerEnd = drawnRangeEnd + defaultTraceLayerWidth;
		if(layerEnd < visibleEnd) {
			layerEnd = visibleEnd;
		}
		[self positionTraceLayerFromStart:drawnRangeEnd toEnd:layerEnd clipRect:clipRect clearOtherLayers:NO];
	}
}



/// Positions a trace layer between two coordinates of the view along the axis, marks it for display, and returns the layer if it could be positioned.
/// - Parameters:
///   - start: The suggested position of the leading edge of the layer's frame.
///   - end: The suggested position of the trailing edge of the layer's frame.
///   - clipRect: The current visible rectangle of the view (sent only to avoid recomputing it).
///   - clearOtherLayers: Whether other trace layers should be removed from the view (and placed in the reuse pool).
-(nullable CALayer *)positionTraceLayerFromStart:(float)start toEnd:(float)end clipRect:(NSRect)clipRect clearOtherLayers:(BOOL)clearOtherLayers {
	
	/// We don't position a trace layer before the start or after the end of traces
	if(start < 0) {
		start = 0;
	}
	float traceEnd = (self.trace.chromatogram.readLength - self.sampleStartSize) * self.hScale;
	if(end >= traceEnd) {
		end = traceEnd;
	}
	if(end-start <= 1) {
		return nil;
	}
	
	NSArray *sublayers = traceLayerParent.sublayers;
	CALayer *traceLayer;
	BOOL placeLeft = NO; /// whether the layer will be placed at the left of the clipRect (scrolling)
	if(clearOtherLayers) {
		traceLayer = traceLayerFillingClipRect? traceLayerFillingClipRect : sublayers.firstObject;
		NSInteger count = sublayers.count;
		if(traceLayer && count > 1) {
			/// We remove other trace layers from the view, which we can't do with fast enumeration
			/// unless we make a copy of the sublayers array, which may take more time
			for (long i = 0; i < count; i++) {
				CALayer *aLayer = sublayers[i];
				if(aLayer != traceLayer) {
					[self removeTraceLayer:aLayer];
					count--;
					i--;
				}
			}
		}
	} else {
		/// Here, we try to reuse a layer without clearing those already showing traces.
		/// This path should be taken during scrolling / overdraw.
		placeLeft = start < drawnRangeStart;
		/// We first try to get a layer from the pool of unused layers
		traceLayer = traceLayers.anyObject;
		if(traceLayer) {
			[traceLayers removeObject:traceLayer]; /// It is therefore no longer unused
		} else {
			/// Otherwise, we reuse a layer that is positioned in the view.
			/// If we should place it at the left, we use the last layer (the one at the right) or vise versa.
			CALayer *layer = placeLeft? sublayers.lastObject : sublayers.firstObject;
			NSRect bounds = layer.bounds;
			if(layer && !layer.needsDisplay && !NSIntersectsRect(bounds, clipRect)) {
				/// The layer to reuse must not be visible nor marked for display.
				traceLayer = layer;
				if(placeLeft) {
					/// We adjust the coordinate of the drawn section of the traces to reflect the fact that the reused layer no longer contributes to that
					/// Here we assume that the layer is contiguous to another one.
					drawnRangeEnd = bounds.origin.x;
				} else {
					drawnRangeStart = NSMaxX(bounds);
				}
			}
		}
	}
	
	if(!traceLayer) {
		traceLayer = self.newTraceLayer;
		if(!traceLayer) {
			return nil;
		} else if(clearOtherLayers) {
			[traceLayerParent addSublayer:traceLayer];
		}
	}
	
	if(clearOtherLayers) {
		drawnRangeStart = start;
		drawnRangeEnd = end;
	} else {
		if(placeLeft) {
			/// A layer placed at the left is inserted first among its siblings.
			[traceLayerParent insertSublayer:traceLayer atIndex:0];
			drawnRangeStart = start;
		} else {
			/// A layer placed at the right is inserted at the last position
			/// The order of layers in the sublayers array should thus reflect their positions from left to right.
			[traceLayerParent addSublayer:traceLayer];
			drawnRangeEnd = end;
		}
	}
	
	/// The bottom edge of the layer clips the trace curve if it goes below 0, considering that the curve is 1 pt thick.
	CGRect layerBounds = CGRectMake(start, -0.5, end-start, NSMaxY(clipRect) + 0.5);
	traceLayer.bounds = layerBounds;
	traceLayer.position = layerBounds.origin;  /// This ensure that the coordinates in the layer are the same as those in the view
	[traceLayer setNeedsDisplay]; /// In case the bounds haven't changed, we mark the positioned layer for display
	
	return traceLayer;
}


- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
	if(layer.superlayer == traceLayerParent) {
		/// We assume that the whole layer is redrawn (no method calls partial redrawing), but this isn't much flexible.
		[self drawTracesInRect:layer.bounds context:ctx];
		self.needsDisplayTraces = NO;
	}
}



/// Draws trace-related elements in the view.
/// - Parameters:
///   - dirtyRect: The rectangle in which to draw, which is the same in view coordinates and layer coordinate.
///   We don't use the clipping bounding box of the context, as some say it can be costly to query.
///   - ctx: The graphics context in which we draw.
- (void)drawTracesInRect:(NSRect) dirtyRect context:(CGContextRef) ctx {
	
	if(_loadedTraces.count == 0) {
		return;
	}
	
	float rectStart = NSMinX(dirtyRect);
	float rectEnd = NSMaxX(dirtyRect);
	if(_needsDisplayTraces) {
		/// In this case, any previous drawing is obsolete, so we make sure that the rendered range reflects the region that is redrawn.
		drawnRangeStart = rectStart;
		drawnRangeEnd = rectEnd;
	}
	
	float hScale = self.hScale;
	float vScale = self.vScale;
	float sampleStartSize = self.sampleStartSize;
	float startSize = rectStart/hScale + sampleStartSize;	/// the size (in base pairs) at the start of the dirty rect
	float endSize = rectEnd/hScale + sampleStartSize;
	Chromatogram *sample = self.trace.chromatogram;
	NSData *sizeData = sample.sizes;
	const float *sizes = sizeData.bytes;
	long nScans = sizeData.length / sizeof(float);
	if(nScans == 0) {
		return;
	}
	
	/// We show offscale regions (with vertical rectangles)
	/// We don't drawn them if we have traces from several samples and if a marker label is enabled,
	/// as these regions can mask the edges  of this label or its bin labels
	NSData *offscaleRegions = sample.offscaleRegions;
	NSColor *currentOffscaleColor;
	NSArray *offScaleColors = self.colorsForOffScaleRegions;
	NSInteger colorCount = offScaleColors.count;
	if (self.showOffscaleRegions && offscaleRegions.length > 0 && (visibleTraces.count == 1 || self.channel < 0) &&
		!self.enabledMarkerLabel) {
		/// channel is normally -1 if we show traces for the same sample. In this case, we can draw off-scale regions
		const OffscaleRegion *regions = offscaleRegions.bytes;
		for (int i = 0; i < offscaleRegions.length/sizeof(OffscaleRegion); i++) {
			OffscaleRegion const *region = &regions[i];
			int32_t startScan = region->startScan;
			int32_t regionWidth = region->regionWidth;
			int32_t endScan = startScan + regionWidth;
			if(endScan >= nScans) {
				break;		/// A safety measure, this should never happen.
			}
			float regionEnd = sizes[endScan];
			
			if(regionEnd >= startSize) {
				float regionStart = sizes[startScan];
				if(regionStart <= endSize) {
					float xStart = (regionStart - sampleStartSize) * hScale;
					float xWidth = (regionEnd - regionStart) * hScale;
					float scanWidth = xWidth/regionWidth;
					ChannelNumber channel = region->channel;
					if(channel >= 0 && channel < colorCount) {
						NSColor *color = offScaleColors[channel];
						if(color != currentOffscaleColor) {
							CGContextSetFillColorWithColor(ctx, color.CGColor);
							currentOffscaleColor = color;
						}
						/// we place the rectangle at half a scan to the left, so that it is centered around the saturated scans
						CGContextFillRect(ctx, CGRectMake(xStart - scanWidth*0.5, 0, xWidth, NSMaxY(self.bounds)));
					}
				} else {
					break;
				}
			}
		}
	}
	
	/// we draw the fluorescence curve(s) from left to right.
	CGFloat lowerY = threshold;
	int16_t lowerFluo = threshold / vScale; 	/// to quickly evaluate if some scans should be drawn
	
	int maxPointsInCurve = appleSilicon ? 40 : 400;	  /// we stoke the curve if it reaches this number of points.
	NSPoint pointArray[maxPointsInCurve];          /// points to add to the curve
	int startScan = 0, maxScan = 0;	/// we will draw traces for scan between these scans.
	sample = nil;
	float lineWidth = 1.0;
	
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
			sizeData = sample.sizes;
			sizes = sizeData.bytes;
			
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
		
		/// Filling peaks resulting from crosstalk.
		if(self.paintCrosstalkPeaks && !self.enabledMarkerLabel) {
			/// We don't fill a marker label is enabled, as if may make bins harder to see.
			for(PeakLabel *peakLabel in self.peakLabels) {
				/// If several traces are visible, there are no peak labels, so the loop should run at most once.
				int peakEndScan = peakLabel.endScan;
				if(peakEndScan >= startScan) {
					if(peakEndScan >= maxScan) {
						break;
					}
					int peakStartScan = peakLabel.startScan;
					float peakStartSize = sizes[peakStartScan];
					if(peakStartSize <= endSize && peakStartScan < peakEndScan) {
						int offScaleChannel = -(peakLabel.crossTalk + 1);
						if(offScaleChannel >= 0 && offScaleChannel <= colorCount) {
							float x = (peakStartSize- sampleStartSize)*hScale;
							float y = -1;
							CGPoint pointArray[peakEndScan - peakStartScan + 3];
							pointArray[0] = CGPointMake(x, y);
							int nPointsInPath = 1;
							
							for (int scan = peakStartScan; scan <= peakEndScan; scan++) {
								x = (sizes[scan] - sampleStartSize) * hScale;
								y = fluo[scan] * vScale;
								if(y < lowerY) {
									y = lowerY -1;
								}
								pointArray[nPointsInPath++] = CGPointMake(x, y);
							}
							x = (sizes[peakEndScan] - sampleStartSize) * hScale;
							pointArray[nPointsInPath++] = CGPointMake(x, -1);
							
							NSColor *color = offScaleColors[offScaleChannel];
							if(color !=currentOffscaleColor) {
								currentOffscaleColor = color;
								CGContextSetFillColorWithColor(ctx, color.CGColor);
							}
							CGContextBeginPath(ctx);
							CGContextAddLines(ctx, pointArray, nPointsInPath);
							CGContextClosePath(ctx);
							CGContextFillPath(ctx);
						}
					} else {
						break;
					}
				}
			}
		}
		
		NSColor *strokeColor = TraceView.colorsForChannels[traceToDraw.channel];
		/// We will stroke the clicked trace with a thicker line.
		float currentLineWidth = traceToDraw == _clickedTrace? 2.0 : 1.0;
		if(currentLineWidth != lineWidth) {
			lineWidth = currentLineWidth;
			CGContextSetLineWidth(ctx, lineWidth);
		}
		if(lineWidth > 1) {
			/// and a lighter color
			CGContextSetStrokeColorWithColor(ctx, [strokeColor  blendedColorWithFraction:0.3 ofColor:NSColor.whiteColor].CGColor);
		} else {
			CGContextSetStrokeColorWithColor(ctx, strokeColor.CGColor);
		}
		
		/// We add the first point to draw to the array
		float lastX = (sizes[startScan] - sampleStartSize)*hScale;
		float y = fluo[startScan]*vScale;
		if (y < lowerY) {
			y = lowerY -1;
		}
		pointArray[0] = CGPointMake(lastX, y);
		int pointsInPath = 1;		/// current number of points being added
		BOOL outside = NO;			/// whether a scan is to the right (outside) the dirty rect. Used to determine when to stop drawing.
		
		int scan = startScan+1;
		while(scan <= maxScan && !outside) {
			float size = sizes[scan];
			if(size > endSize) {
				outside = YES;
			}
			float x = (size - sampleStartSize) * hScale;
			
			int16_t scanFluo = fluo[scan];
			if (scan < maxScan-1) {
				/// we may skip a point that is too close from previously drawn scans and not a local minimum / maximum
				/// or that is lower than the fluo threshold
				int16_t previousFluo = fluo[scan-1];
				int16_t nextFluo = fluo[scan+1];
				if((x-lastX < 1 && !(previousFluo >= scanFluo && nextFluo > scanFluo) &&
					!(previousFluo <= scanFluo && nextFluo < scanFluo)) || scanFluo < lowerFluo) {
					/// and that is not the first/last of a series of scans under the lower threshold
					if(!(scanFluo <= lowerFluo && (previousFluo > lowerFluo || nextFluo > lowerFluo))) {
						/// We must draw the first point and the last point outside the dirty rect
						if(!outside) {
							scan++;
							continue;
						}
					}
				}
			}
			lastX = x;
			y = scanFluo * vScale;
			if (y < lowerY) {
				y = lowerY -1;
			}
			
			CGPoint point = CGPointMake(x, y);
			pointArray[pointsInPath++] = point;
			if((pointsInPath == maxPointsInCurve || outside || scan == maxScan -1)) {
				if(appleSilicon) {
					/// On Apple Silicon Macs, stroking a path is faster (the GPU is used)
					CGContextBeginPath(ctx);
					CGContextAddLines(ctx, pointArray, pointsInPath);
					CGContextStrokePath(ctx);
				} else {
					/// On intel Macs (which cannot use the GPU for drawing), stroking line segments is faster.
					CGContextStrokeLineSegments(ctx, pointArray, pointsInPath);
				}
				pointArray[0] = point;
				pointsInPath = 1;
			} else if(!appleSilicon) {
				/// On intel, we draw unconnected depend line segments, so the end of each segment is the start of the next one
				pointArray[pointsInPath++] = point;
			}
			scan++;
		}
	}
//	CGContextSetStrokeColorWithColor(ctx, NSColor.blackColor.CGColor);
//	CGContextStrokeRect(ctx, dirtyRect);
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
	return CGPointMake([self xForScan:scan], fluo[scan] * _vScale);
}


- (int)scanForX:(float) position {
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
		NSRect bounds = self.bounds;
		if(bounds.size.height > 0) {
			self.vScale = NSMaxY(bounds)/_topFluoLevel;
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
		NSRect bounds = self.bounds;
		if(bounds.size.height > 0) {
			self.vScale = NSMaxY(bounds)/_topFluoLevel;
		}
	}
}


- (void)setVScale:(float)scale {
	if (scale != _vScale) {
		_vScale = scale;
		if(!_resizedWithAnimation) {
			self.needsDisplayTraces = YES;
			self.needsRepositionFragmentLabels = YES;
		} else {
			/// If the vertical scale is changed with animation, we reposition fragment labels immediately
			/// in layout() if would be too late.
			[self repositionLabels:self.fragmentLabels];
			[FragmentLabel avoidCollisionsInView:self];
		}
		self.vScaleView.needsDisplay = YES;
	}
}


-(BOOL) scrollRectToVisible:(NSRect)rect {
	/// overridden because our visible rect is particular and because the trace scroll view filters scroll events
	return [self scrollRectToVisible:rect animate:NO];
}


-(BOOL)scrollRectToVisible:(NSRect)rect animate:(BOOL)animate {
	float startX = rect.origin.x;
	if(startX < 0) {
		return NO;
	}
	
	float endX = NSMaxX(rect);
	if(endX > NSMaxX(self.bounds)) {
		return NO;
	}
	
	NSRect clipRect = self.clipRect;
	if(startX < clipRect.origin.x) {
		[self scrollPoint:NSMakePoint(startX, 0) animate:animate];
		return YES;
	}
	
	if(endX > NSMaxX(clipRect)) {
		[self scrollPoint:NSMakePoint(endX - clipRect.size.width, 0) animate:animate];
		return YES;
	}
	
	return NO;
}


- (void)scrollPoint:(NSPoint)point {
	[self scrollPoint:point animate:NO];
}


- (void)scrollPoint:(NSPoint)point animate:(BOOL) animate {
	BaseRange visibleRange = self.visibleRange;
	visibleRange.start = point.x/self.hScale + self.sampleStartSize;
	[self setVisibleRange:visibleRange animate:animate];
}


- (void)setVisibleOrigin:(float)newVisibleOrigin {
	if (newVisibleOrigin != _visibleOrigin) {
		self.isMoving = YES;
		/// we set the current mouse location in the view coordinate system as it changes during scrolling
		/// (since the view scrolls behind the mouse) and should show in the ruler view
		/// to compute it, we need to record the previous visible origin (the new mouse location must set it after the scroll)
		float previous = _visibleOrigin;
		_visibleOrigin = newVisibleOrigin;
		
		NSClipView *clipView = (NSClipView *)self.superview;
		[clipView scrollToPoint:NSMakePoint(newVisibleOrigin - self.leftInset, 0)];
		[self.enclosingScrollView reflectScrolledClipView:clipView];
		traceLayerFillingClipRect = nil;  /// The layer showing traces no longer fits the visible rectangle
		
		if(!_resizedWithAnimation) {
			[self setNeedsLayoutTraceLayer]; /// We need to position trace layers during scrolling.
			///as our markerView doesn't scroll, it needs to reposition its marker labels to reflect our range
			self.markerView.needsRepositionLabels = YES;
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
		if(!_resizedWithAnimation) {
			self.markerView.needsRepositionLabels = YES;
		}
	}
}


/// Makes the view as wide as it needs to be,
- (void)fitToIntrinsicContentSize {
	if(self.hScale >= 0) {
		NSSize newSize = self.intrinsicContentSize;
		if (!NSEqualSizes(newSize, self.frame.size)) {
			[self setFrameSize:newSize];
		}
	}
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

/// This sets the visible range and vertical scale (should be called after the content is loaded).
- (void)getRangeAndScale {
	
	/// we change ivars related to geometry to signify the the view is not in its final state.
	/// We don't use the setters as we don't want the view to actually change the geometry of the view to match these dummy values
	_hScale = -1.0; viewHeight = 0; _visibleRange = MakeBaseRange(0, 2.0);
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
}


- (BOOL)clipsToBounds {
	return YES;
}


- (void)setLeftInset:(float)leftInset {
	_leftInset = leftInset;
	NSScrollView *scrollView = self.enclosingScrollView;
	if(scrollView.documentView == self) {
		NSEdgeInsets insets = scrollView.contentInsets;
		insets.left = leftInset;
		scrollView.contentInsets = insets;
		if(self.hScale > 0) {
			/// We update our geometry to maintain the visible range
			self.hScale = self.visibleWidth / _visibleRange.len;
			self.visibleOrigin = (_visibleRange.start - _sampleStartSize) * _hScale;
		}
	}
}


- (void)setBoundsOrigin:(NSPoint)newOrigin {
	/// bounds x origin must be reflected by the top ruler view and the marker view, so that graduations and markers show at the correct position relative to the traces
	[super setBoundsOrigin:newOrigin];
	[self.markerView setBoundsOrigin:NSMakePoint(newOrigin.x,0)];
	[self.rulerView setBoundsOrigin:NSMakePoint(newOrigin.x, 0)];
	VScaleView *vScaleView = self.vScaleView;
	NSPoint point = [vScaleView convertPoint:NSMakePoint(0, 0) fromView:self];
	[vScaleView setBoundsOrigin:NSMakePoint(0, -point.y + vScaleView.bounds.origin.y)];
	self.needsRepositionLabels = YES;		/// This is because bin labels must span the whole view vertically, regardless of the bounds origin.
}


- (NSRect)visibleRect {
	/// overridden as our vScale view hides part of our left region, which ends at our x bounds origin of 0.
	/// So this region is removed from our visible rect;
	NSRect rect = super.visibleRect;
	rect = NSIntersectionRect(rect, self.bounds); /// the visible rect may be taller than our bound under macOS 14+
	float inset = self.leftInset;
	rect.origin.x += inset;
	rect.size.width -= inset;
	if(rect.size.width < 0) {
		rect.size.width = 0;
	}
	return rect;
}


- (float) visibleWidth {
	return self.superview.bounds.size.width - self.leftInset;
}


- (NSRect)clipRect {
	NSRect bounds = self.bounds;
	
	return NSMakeRect(self.visibleOrigin, bounds.origin.y, self.visibleWidth, bounds.size.height);
}


- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
	/// we react to changes in our clipview size to maintain our visible range and fit vertically to this view
	NSSize newSize = self.superview.bounds.size;
	self.resizedWithAnimation = NSAnimationContext.currentContext.allowsImplicitAnimation;
	
	if(newSize.height != oldSize.height) {
		[self fitVertically];
	}
	
	if(newSize.width != oldSize.width && self.hScale > 0) {
		self.hScale = self.visibleWidth / _visibleRange.len;
		self.visibleOrigin = (_visibleRange.start - _sampleStartSize) * _hScale;
		if(_resizedWithAnimation) {
			/// To reposition marker labels in sync with the animation, we need to reposition them now.
			/// We do it now because resizeWithOldSuperviewSize: is not called on the marker view when the context allows implicit animations.
			/// We need to resize the marker view to its final size, otherwise the markers label will not be positioned properly.
			MarkerView *markerView = self.markerView;
			NSSize markerViewSize = markerView.frame.size;
			markerViewSize.width = newSize.width;
			[markerView setFrameSize:markerViewSize];
			[markerView repositionLabels:markerView.markerLabels];
		}
	}
	
	self.resizedWithAnimation = NO;
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
	/// as we the view doesn't scroll vertically, we make sure its height is that of the visible rect of the clipview
	/// we have to consider the height of the horizontal ruler, which overlaps the clipView. We don't want to show behind that
	float topInset = 0;
	RulerView *rulerView = self.rulerView;
	NSRect clipViewFrame = self.superview.frame;
	if(rulerView && !rulerView.hidden) {
		topInset = NSIntersectionRect(rulerView.frame, clipViewFrame).size.height;
	}
	viewHeight = round(clipViewFrame.size.height - topInset);
	NSRect frame = self.frame;
	if(viewHeight != frame.size.height) {
		[self setFrameSize:NSMakeSize(frame.size.width, viewHeight)];
		float topFluoLevel = self.topFluoLevel;
		float boundsOrigin = self.bounds.origin.y;
		if(topFluoLevel > 0) {
			if(self.autoScaleToHighestPeak) {
				/// To maintain the 20-point margin above the highest peak, the top fluo level must be updated
				self.topFluoLevel = (viewHeight + boundsOrigin) / (viewHeight - 20 + boundsOrigin) * (topFluoLevel - 20/_vScale);
			} else {
				/// Otherwise, the topFluoLevel remains the same, but the vScale need to be changed to accommodate the difference in height.
				self.vScale =  (viewHeight + boundsOrigin)/topFluoLevel;
			}
		}
		
		if(dashedLineLayer) {
			/// we make the dashed line layer as tall as the view
			dashedLineLayer.bounds = CGRectMake(0, 0, 1, viewHeight);
			CGMutablePathRef path = CGPathCreateMutable();
			CGPathMoveToPoint(path, NULL, 0.5, NSMaxY(dashedLineLayer.bounds));
			CGPathAddLineToPoint(path, NULL, 0.5,0);
			dashedLineLayer.path = path;
			CGPathRelease(path);
		}
	}
}


- (void)setFrameSize:(NSSize)newSize {
	NSSize oldSize = self.frame.size;
	self.isMoving = YES;
	_isResizing = YES;
	[super setFrameSize:newSize];
	_isResizing = NO;
	if(_resizedWithAnimation) {
		/// If the size changes (without a change in vScale or hScale), the marker labels need to be repositioned
		/// to occupy the whole view height. Bins are resized by the marker labels.
		/// We don't defer that, otherwise labels would not move in sync with the animation.
		[self repositionLabels:self.markerLabels];
		[self repositionLabels:self.fragmentLabels];
		[FragmentLabel avoidCollisionsInView:self];
		[self rescaleTraceLayersWithOldSize:oldSize];
	} else {
		/// If we don't need to animate, it's safer to reposition the layer filling the visible rectangle.
		traceLayerFillingClipRect = nil;
		self.needsRepositionLabels = YES;
		self.needsDisplayTraces = YES;
	}
	[self positionVerticalLineLayer];
}


-(void)setResizedWithAnimation:(BOOL)resizedWithAnimation {
	_resizedWithAnimation = resizedWithAnimation;
}


-(float)topFluoForRange:(BaseRange)range {
	float maxLocalFluo = 0;
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
		NSData *sizeData = sample.sizes;
		const float *sizes = sizeData.bytes;
		long nSizes = sizeData.length / sizeof(float);
		const Peak *peaks = tracePeaks.bytes;
		long nPeaks = tracePeaks.length/sizeof(Peak);
		int minScan = sample.minScan, maxScan = sample.maxScan;
		NSData *fluoData = useRawData? trace.primitiveRawData : [trace adjustedDataMaintainingPeakHeights:NO];
		NSInteger nScans = fluoData.length/sizeof(int16_t);
		const int16_t *fluo = fluoData.bytes;
		for(int i = 0; i < nPeaks; i++) {
			const Peak *peakPTR = &peaks[i];
			if(ignoreCrosstalk && peakPTR->crossTalk < 0) {
				continue;
			}
			int scan = peakPTR->startScan + peakPTR->scansToTip;
			if(peakEndScan(peakPTR) > maxScan || scan >= nSizes || sizes[scan] > endSize || scan >= nScans) {
				break;
			}
			if(peakPTR->startScan < minScan || sizes[scan] < startSize) {
				continue;
			}
			
			if(fluo[scan] > maxLocalFluo) {
				maxLocalFluo = fluo[scan];
			}
		}
	}
	
	
	maxLocalFluo += maxLocalFluo * 20/NSMaxY(self.bounds);		/// we leave a 20-point margin above the highest peak
	return maxLocalFluo;
}


- (void)setTopFluoLevel:(float)fluo withAnimation:(BOOL)animate {
	if(!animate) {
		self.topFluoLevel = fluo;
	} else {
		self.animator.topFluoLevel = fluo;
	}
}


- (void)scaleToHighestPeakWithAnimation:(BOOL) animate {
	if(visibleTraces.count > 0) {
		float fluo = [self topFluoForRange:self.visibleRange];
		if(fluo != self.topFluoLevel && fluo > 0) {
			[self setTopFluoLevel:fluo withAnimation:animate];
		}
	}
}


- (void)updateViewLength {
	float maxEndSize = self.defaultRange.start + self.defaultRange.len;
	Chromatogram *sample = self.trace.chromatogram;
	float length = sample == nil? 600.0 : sample.readLength;
	_sampleStartSize = sample.startSize;
	viewLength = (maxEndSize > length) ? maxEndSize - _sampleStartSize : length - _sampleStartSize;
}


- (NSSize)intrinsicContentSize {
	float hScale = self.hScale;
	if(hScale < 0) {
		hScale = 0;
	}
	return NSMakeSize(viewLength * hScale - self.bounds.origin.x, viewHeight);
}


-(void)setIsMoving:(BOOL)moving {
	if(_isMoving != moving) {
		_isMoving = moving;
		if(moving) {
			/// when the view gets resized, we remove tracking areas. During zoom, we don't reposition the areas, so their position is invalid.
			/// After resizing, they will be rebuilt
			for(NSTrackingArea *area in self.trackingAreas) {
				if(area != trackingArea) {
					[self removeTrackingArea:area];
				}
			}
			if(self.showPeakTooltips) {
				[self removeAllToolTips];
			}
		}
	}
}



# pragma mark - changes in display settings

- (void)viewDidChangeEffectiveAppearance {
	/// We don't change the appearance immediately to workaround a macOS 14 bug with CATextLayer (used for bin and marker names).
	/// This bug prevents the foreground (text) color from changing if the update occurs too closely to the change in appearance (even if the color used is a static color).
	if(!(needsUpdateAppearance)) {
		[self performSelector:@selector(updateAppearance) withObject:nil afterDelay:0.1];
	}
}


- (void)viewDidMoveToWindow {
	if(self.effectiveAppearance != NSApp.effectiveAppearance) {
		/// If the view wasn't visible when the app last changed appearance, it may not have changed appearance.
		/// It gets its new appearance when it shows, but that will require a short delay to workaround a bug, making the view
		/// appear in an incorrect appearance for a short time. So we update it now.
		[self updateAppearance];
	}
}


-(void) updateAppearance {
	self.needsUpdateLabelAppearance = YES;
	needsUpdateAppearance = YES;
	/// we tell other views of the row to update their appearance.
	self.markerView.needsUpdateLabelAppearance = YES;
	self.rulerView.needsChangeAppearance = YES;
}


- (void)setShowDisabledBins:(BOOL)showBins {
	_showDisabledBins = showBins;
	if(!self.trace && self.marker) {		/// we do not modify bin visibility if we only show a marker
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
		if(showBins) {
			[self labelNeedsRepositioning:markerLabel]; /// required to avoid overlap in bin names
		}
	}
}


- (void)setShowOffscaleRegions:(BOOL)showOffscaleRegions {
	_showOffscaleRegions = showOffscaleRegions;
	if(_hScale > 0) {
		/// offScale regions are drawn together with traces, so:
		self.needsDisplayTraces = YES;
	}
}


- (void)setShowPeakTooltips:(BOOL)showPeakTooltips {
	_showPeakTooltips = showPeakTooltips;
	if(!showPeakTooltips) {
		for (PeakLabel *label in self.peakLabels) {
			[label removeTooltip];
		}
	}
}


- (void)setPaintCrosstalkPeaks:(BOOL)paintCrosstalkPeaks {
	_paintCrosstalkPeaks = paintCrosstalkPeaks;
	self.needsDisplayTraces = YES;
}


- (void)setShowRawData:(BOOL)showRawData {
	_showRawData = showRawData;
	if(self.autoScaleToHighestPeak) {
		[self scaleToHighestPeakWithAnimation:YES];
	}
	self.needsRepositionFragmentLabels = YES; /// because peak heights may change
	self.needsDisplayTraces = YES;
}


- (void)setMaintainPeakHeights:(BOOL)maintainPeakHeights {
	_maintainPeakHeights = maintainPeakHeights;
	self.needsDisplayTraces = YES;
	if(self.autoScaleToHighestPeak) {
		[self scaleToHighestPeakWithAnimation:YES];
	}
	self.needsRepositionFragmentLabels = YES; /// because peak heights may change
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


- (void)setDisplayedChannels:(NSArray<NSNumber *> *)displayedChannels  {
	NSArray *previousTraces = visibleTraces;
	_displayedChannels = [NSArray arrayWithArray:displayedChannels];
	NSArray<Trace *> *loadedTraces = self.loadedTraces;
	if(loadedTraces.firstObject.channel != loadedTraces.lastObject.channel) {
		visibleTraces = [loadedTraces filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Trace *trace, NSDictionary<NSString *,id> * _Nullable bindings) {
			return [self.displayedChannels containsObject: @(trace.channel)];
		}]];
		NSInteger visibleTraceCount = visibleTraces.count;
		Trace *referenceTrace = visibleTraceCount > 0? visibleTraces.firstObject : loadedTraces.firstObject;
	
		self.channel = visibleTraceCount == 0? noChannelNumber :
		(visibleTraceCount > 1? multipleChannelNumber : referenceTrace.channel);
		self.needsRepositionLabels = YES;
		self.trace = referenceTrace;
		self.markerView.hidden = self.channel == multipleChannelNumber || self.trace.isLadder;
		self.panel = self.panelToShow;
		self.needsDisplayTraces = YES;
		if(self.autoScaleToHighestPeak) {
			/// when displayed traces change, we may have to rescale to the highest peak
			/// we animate only if at least one trace was displayed before
			BOOL animate = [visibleTraces sharesObjectsWithArray:previousTraces];
			[self scaleToHighestPeakWithAnimation:animate];
		}
	}
}


- (void)setVScaleView:(VScaleView *)vScaleView {
	_vScaleView = vScaleView;
	NSPoint point = [vScaleView convertPoint:NSMakePoint(0, 0) fromView:self];
	[vScaleView setBoundsOrigin:NSMakePoint(0, -point.y)];
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


- (NSArray<NSColor *> *)colorsForOffScaleRegions {
	if(_colorsForOffScaleRegions.count < 5) {
		float fraction = [self.effectiveAppearance.name isEqualToString:NSAppearanceNameDarkAqua]? 0.3 : 0.2;
		_colorsForOffScaleRegions = NSArray.new;
		ChannelNumber i = 0;
		for (NSColor *color in TraceView.colorsForChannels) {		/// the offscale color as derived from the channel color
			float usedFraction = i == blackChannelNumber && fraction <= 0.3 ? fraction : fraction;
			_colorsForOffScaleRegions = [_colorsForOffScaleRegions arrayByAddingObject:[color colorWithAlphaComponent:usedFraction]];
			
			i++;
		}
	}
	return _colorsForOffScaleRegions;
}


- (void)updateFragmentLabelBackgroundColor {
	CGColorRelease(_fragmentLabelBackgroundColor);
	_fragmentLabelBackgroundColor = CGColorCreateCopyWithAlpha(traceViewBackgroundColor.CGColor, 0.7);
}


- (CGColorRef)fragmentLabelBackgroundColor {
	if(!_fragmentLabelBackgroundColor) {
		[self updateFragmentLabelBackgroundColor];
	}
	return _fragmentLabelBackgroundColor;
}


- (void)updateFragmentLabelStringColor {
	CGColorRelease(_fragmentLabelStringColor);
	_fragmentLabelStringColor = CGColorRetain(NSColor.textColor.CGColor);
}


- (CGColorRef)fragmentLabelStringColor {
	if(!_fragmentLabelStringColor) {
		[self updateFragmentLabelStringColor];
	}
	return _fragmentLabelStringColor;
}


- (void)updateAlleleLabelBackgroundColor {
	CGColorRelease(_alleleLabelBackgroundColor);
	ChannelNumber channel = self.channel;
	NSArray<NSColor *> *colors = LabelView.colorsForChannels;
	if(channel >= 0 && channel < colors.count) {
		_alleleLabelBackgroundColor = CGColorCreateCopyWithAlpha(colors[channel].CGColor, 0.7);
	} else {
		_alleleLabelBackgroundColor = CGColorRetain(NSColor.systemGrayColor.CGColor);
	}
}


- (CGColorRef)alleleLabelBackgroundColor {
	if(!_alleleLabelBackgroundColor) {
		[self updateAlleleLabelBackgroundColor];
	}
	return _alleleLabelBackgroundColor;
}


- (void)updateBinLabelColor {
	CGColorRelease(_binLabelColor);
	_binLabelColor = CGColorRetain([NSColor colorNamed:@"binLabelColor"].CGColor);
}


- (CGColorRef)binLabelColor {
	if(!_binLabelColor) {
		[self updateBinLabelColor];
	}
	return _binLabelColor;
}


- (void)updateHoveredBinLabelColor {
	CGColorRelease(_hoveredBinLabelColor);
	_hoveredBinLabelColor = CGColorRetain([NSColor colorNamed:@"hoveredBinLabelColor"].CGColor);
}


- (CGColorRef)hoveredBinLabelColor {
	if(!_hoveredBinLabelColor) {
		[self updateHoveredBinLabelColor];
	}
	return _hoveredBinLabelColor;
}


- (void)updateRegionLabelEdgeColor {
	CGColorRelease(_regionLabelEdgeColor);
	_regionLabelEdgeColor = CGColorRetain([NSColor colorNamed:@"regionLabelEdgeColor"].CGColor);
}


- (CGColorRef)regionLabelEdgeColor {
	if(!_regionLabelEdgeColor) {
		[self updateRegionLabelEdgeColor];
	}
	return _regionLabelEdgeColor;
}


- (void)updateBinNameBackgroundColor {
	CGColorRelease(_binNameBackgroundColor);
	_binNameBackgroundColor = CGColorRetain([NSColor colorNamed:@"binNameBackgroundColor"].CGColor);
}


- (CGColorRef)binNameBackgroundColor {
	if(!_binNameBackgroundColor) {
		[self updateBinNameBackgroundColor];
	}
	return _binNameBackgroundColor;
}


- (void)updateHoveredBinNameBackgroundColor {
	CGColorRelease(_hoveredBinNameBackgroundColor);
	_hoveredBinNameBackgroundColor = CGColorRetain([NSColor colorNamed:@"hoveredBinNameBackgroundColor"].CGColor);
}


- (CGColorRef)hoveredBinNameBackgroundColor {
	if(!_hoveredBinNameBackgroundColor) {
		[self updateHoveredBinNameBackgroundColor];
	}
	return _hoveredBinNameBackgroundColor;
}


- (void)updateTraceViewMarkerLabelBackgroundColor {
	CGColorRelease(_traceViewMarkerLabelBackgroundColor);
	_traceViewMarkerLabelBackgroundColor = CGColorRetain([NSColor colorNamed:@"traceViewMarkerLabelBackgroundColor"].CGColor);
}


- (CGColorRef)traceViewMarkerLabelBackgroundColor {
	if(!_traceViewMarkerLabelBackgroundColor) {
		[self updateTraceViewMarkerLabelBackgroundColor];
	}
	return _traceViewMarkerLabelBackgroundColor;
}


- (void)updateTraceViewMarkerLabelAllowedRangeColor {
	CGColorRelease(_traceViewMarkerLabelAllowedRangeColor);
	_traceViewMarkerLabelAllowedRangeColor = CGColorRetain([NSColor colorNamed:@"traceViewMarkerLabelAllowedRangeColor"].CGColor);
}


- (CGColorRef)traceViewMarkerLabelAllowedRangeColor {
	if(!_traceViewMarkerLabelAllowedRangeColor) {
		[self updateTraceViewMarkerLabelAllowedRangeColor];
	}
	return _traceViewMarkerLabelAllowedRangeColor;
}


#pragma mark - reacting to mouse and key events

- (BOOL)acceptsFirstResponder {
	return YES;
}


- (BOOL)resignFirstResponder {
	self.rulerView.currentPosition = -10000;
	self.clickedTrace = nil;
	for (ViewLabel *label in self.viewLabels) {
		/// We deselect any highlighted label that is not the enabled marker label.
		if(label != _enabledMarkerLabel) {
			if([label respondsToSelector:@selector(attachedPopover)]) {
				if([(RegionLabel *)label attachedPopover] == nil) {
					/// if the label has a popover, this method is likely call because the popover is spawn
					/// in this case we don't de-highlight the label. We only do it if it has no popover attached.
					label.highlighted = NO;
				}
			} else {
				label.highlighted = NO;
			}
		}
	}
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
		if(hoveredMarkerLabel.editState == editStateBins) {
			/// if the marker label is in this edit state, we show that bins can be added manually.
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
	hoveredBinLabel = nil;
	hoveredPeakLabel = nil;
	hoveredMarkerLabel = nil;
	[super mouseExited:event];
	self.rulerView.currentPosition = -10000;		/// this removes the display of the current cursor position from the ruler view
}


static BOOL pressure = NO; /// to react only upon force click and not after

- (void)pressureChangeWithEvent:(NSEvent *)event {
	/// upon force click, we either select a bin (to edit it) or create a peak that could be missing at the location
	if(!pressure && event.stage >= 2.0) {
		pressure = YES;
		NSPoint mouseLocation = [self convertPoint:event.locationInWindow fromView:nil];
		
		for(FragmentLabel *fragmentLabel in self.fragmentLabels) {
			/// If the click happens to be in a fragment label, we do nothing.
			if(NSPointInRect(mouseLocation, fragmentLabel.frame)) {
				return;
			}
		}
		
		if(visibleTraces.count == 1) {
			/// The user may be trying to add a peak.
			int scan = [self scanForX:mouseLocation.x];
			NSPoint point = [self pointForScan:scan];
			if(point.y >= mouseLocation.y) { /// The user has clicked below the curve.
				Peak addedPeak = [self.trace missingPeakForScan:scan useRawData:self.showRawData];
				if(addedPeak.startScan > 0 && [self.trace insertPeak:addedPeak]) {
					[self.window.undoManager setActionName:@"Add Peak"];
					return;
				}
			}
		}
		
		if(visibleTraces.count > 1 && self.channel >= 0 && !self.enabledMarkerLabel) {
			/// The user may be trying to click a curve.
			Trace *clickedTrace = [self closestTraceToPoint:mouseLocation withinDistance:3];
			self.clickedTrace = clickedTrace;
			if(clickedTrace) {
				[self.delegate traceView:self didClickTrace:clickedTrace];
				return;
			}
		}
		
		/// The user may be trying to select a bin.
		
		if(NSPointInRect(mouseLocation, self.enabledMarkerLabel.frame)) {
			Mmarker *marker = self.enabledMarkerLabel.region;
			if(marker.editState != editStateBinSet) {
				/// If the click is within the enabled marker label, the user may already be editing individual bins
				/// in which case a force click isn't need. Or they may be editing the marker offset, in which case no bin should be selectable
				/// We only allow to proceed if the user is moving the bin set, which pertains to bin editing.
				return;
			}
		}
		
		for(RegionLabel *markerLabel in self.markerLabels) {
			if(NSPointInRect(mouseLocation, markerLabel.frame)) {
				for(RegionLabel *binLabel in markerLabel.binLabels) {
					if(!binLabel.hidden && NSPointInRect(mouseLocation, binLabel.frame)) {
						Mmarker *marker = ((Bin *)binLabel.region).marker;
						marker.editState = editStateBins;
						binLabel.highlighted = YES;
						return;
					}
				}
				break;
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
		
	if(visibleTraces.count == 1 && !self.enabledMarkerLabel) {
		/// if  there was no peak label at the clicked point, we present the option to add a peak at the mouse location
		/// but we first check if the clicked region corresponds to a peak
		int clickedScan = [self scanForX:self.rightClickedPoint.x];
		NSPoint point = [self pointForScan:clickedScan];
		if(point.y > self.rightClickedPoint.y) {
			/// if the clicked point is below the curve, we do nothing, the user may want to add a missing peak
			Peak addedPeak = [self.trace missingPeakForScan:clickedScan useRawData:self.showRawData];
			if(addedPeak.startScan > 0) {					/// this would be 0 if there there is no peak
				NSMenu *addPeakMenu = NSMenu.new;
				NSMenuItem *item = [[NSMenuItem alloc]initWithTitle:@"Add Peak here"
															 action:@selector(addPeakWithMenuItem:)
													  keyEquivalent:@""];
				[addPeakMenu addItem:item];
				/// We add the peak to the menu item.
				item.representedObject = [NSValue valueWithBytes:&addedPeak objCType:@encode(Peak)];
				item.target = self;
				return addPeakMenu;
			}
		}
	}
	/// The user may be trying to right click a curve.
	Trace *clickedTrace = nil;

	if(visibleTraces.count > 1 && self.channel >= 0) {
		clickedTrace = [self closestTraceToPoint:self.rightClickedPoint withinDistance:3];
		self.clickedTrace = clickedTrace;
	}
	
	if(clickedTrace) {
		NSMenu *menu = NSMenu.new;
		NSString *title = self.genotype? @"Highlight Source Genotype" : @"Highlight Source Sample";
		NSMenuItem *item = [[NSMenuItem alloc]initWithTitle:title
													 action:@selector(highLightSampleWithMenuItem:)
											  keyEquivalent:@""];
		[menu addItem:item];
		item.offStateImage = [NSImage imageNamed:@"looking left"];
		item.representedObject = clickedTrace;
		item.target = self;
		return menu;
	}
	return nil;
}


- (void)highLightSampleWithMenuItem:(NSMenuItem *)sender {
	[self.delegate traceView:self didClickTrace:sender.representedObject];
	sender.representedObject = nil;
}


- (void)addPeakWithMenuItem:(NSMenuItem *)sender {
	NSValue *peakValue = sender.representedObject;
	if(![peakValue isKindOfClass:NSValue.class]) {
		return;
	}
	Peak addedPeak;
	[peakValue getValue:&addedPeak];
	
	if([self.trace insertPeak:addedPeak]) {
		[self.window.undoManager setActionName:@"Add Peak"];
		/// we force the new peak label to be hovered, to help the user know that a peak was added
		[self updatePeakLabels];
		self.needsDisplayTraces = YES;
		int refScan = addedPeak.startScan;
		for(PeakLabel *label in self.peakLabels) {
			int scan = label.startScan;
			if(scan == refScan) {
				label.hovered = YES;
				break;
			}
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



- (void)deleteSelection:(id)sender {
	[self.activeLabel deleteAction:sender];
}



- (void)mouseDown:(NSEvent *)theEvent   {
	[self.window makeFirstResponder:self];
	self.mouseLocation= [self convertPoint:theEvent.locationInWindow fromView:nil];
	self.clickedTrace = nil;
	[super mouseDown:theEvent];
}


/// Return the trace whose (theoretical) curve is closest, and within a distance, to a point.
///
/// The trace is picked among the ``visibleTraces``.
/// The method does not rely on curves drawn by the view.
/// - Parameter point: A point in view coordinate.
/// - Parameter maxDist: The maximum distance (in points) between the point and the curve representing the trace..
- (nullable Trace *)closestTraceToPoint:(NSPoint)point withinDistance:(float)maxDist {
	Trace *closestTrace = nil;
	float x = point.x, y = point.y;
	float sizeAtPoint = [self sizeForX:x];
	float vScale = self.vScale;
	BOOL showRawData = self.showRawData;
	BOOL maintainPeakHeights = self.maintainPeakHeights;
	
	float minDist = INFINITY; /// minimum distance between the point and the curve of a trace.
	/// We compute the distance between the point and the segment linking the scans surrounding the point along the x axis.
	/// Note: this may not be the segment that is the closest to the point, but most of the time it should be.
	for(Trace *trace in visibleTraces) {
		Chromatogram *sample = trace.chromatogram;
		int scan = [sample scanForSize:sizeAtPoint];
		if(scan < 1 || scan >= sample.maxScan) {
			continue;
		}
		NSData *sizeData = sample.sizes;
		long nScans = sizeData.length / sizeof(float);
		if(nScans <= scan) {
			continue;
		}
		const float *sizes = sizeData.bytes;
		int leftScan = sizes[scan] > sizeAtPoint? scan-1 : scan;
		float leftSize = sizes[leftScan];
		float rightSize = sizes[leftScan+1];
		
		int16_t leftFluo = [trace fluoForScan:leftScan useRawData:showRawData maintainPeakHeights:maintainPeakHeights];
		int16_t rightFluo = [trace fluoForScan:leftScan+1 useRawData:showRawData maintainPeakHeights:maintainPeakHeights];
		float leftY = leftFluo * vScale;
		float rightY = rightFluo * vScale;
		float leftX = [self xForSize:leftSize];
		float rightX = [self xForSize:rightSize];
		
		float dist = fabs((rightY - leftY)*x - (rightX - leftX)*y + rightX*leftY - rightY*leftX) /
		sqrtf(pow(rightY-leftY,2) + pow(rightX - leftX,2));
		
		if(dist < minDist) {
			minDist = dist;
			if(minDist <= maxDist) {
				closestTrace = trace;
			}
		}
	}
	
	return closestTrace;
}


- (void)setClickedTrace:(Trace *)clickedTrace {
	if(clickedTrace != _clickedTrace) {
		_clickedTrace = clickedTrace;
		self.needsDisplayTraces = YES;
	}
}


- (IBAction)cancelOperation:(id)sender {
	[self.activeLabel cancelOperation:sender];
	[self.enabledMarkerLabel cancelOperation:sender];
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(menuItem.action == @selector(rename:)) {
		/// Alleles can be renamed from the view.
		if(!self.trace.isLadder &&  [self.activeLabel isKindOfClass:FragmentLabel.class] && !self.activeLabel.clicked) {
			menuItem.title = @"Rename";
			menuItem.hidden = NO;
			return YES;
		}
		menuItem.hidden = YES;
		return NO;
	}
	return [super validateMenuItem:menuItem];
}


/// Sent by the Rename Menu
- (void)rename:(id)sender {
	ViewLabel *activeLabel = self.activeLabel;
	if(!self.trace.isLadder &&  [activeLabel isKindOfClass:FragmentLabel.class] && !activeLabel.clicked) {
		/// Alleles can be renamed via the double click action on fragment labels.
		[activeLabel doubleClickAction:sender];
	}
}


- (void)mouseDragged:(NSEvent *)theEvent   {
	/// used to let the user resize labels of add a new bin
	
	self.mouseLocation = [self convertPoint:theEvent.locationInWindow fromView:nil];
	if(draggedLabel) {
		[draggedLabel mouseDraggedInView];
		return;
	}
	
	ViewLabel *activeLabel = self.activeLabel;
	if(activeLabel.clicked) {
		if(!NSPointInRect(self.clickedPoint, activeLabel.frame)) {
			/// The active label may appear clicked after the mouse button was released when a contextual menu was showing (because no mouseUp: message was sent to us in that case)
			/// Because no mouseDown: is sent to us when he user clicks the view while the menu is open, the label still appears clicked.
			activeLabel.clicked = NO;
		}
		[activeLabel mouseDraggedInView];
		return;
	}
	
	RegionLabel *enabledMarkerLabel = self.enabledMarkerLabel;
	if(enabledMarkerLabel.editState == editStateBins && NSPointInRect(self.clickedPoint, enabledMarkerLabel.frame) && NSPointInRect(self.mouseLocation, enabledMarkerLabel.frame)) {
		/// if the mouse is dragged in the enabled marker label, the user may be trying to add a bin
		/// a bin can be added in the region covered by the unlocked marker label, but it must not overlap an existing bin label
		if(fabs(self.clickedPoint.x - self.mouseLocation.x) > 3) {
			for(RegionLabel *binLabel in enabledMarkerLabel.binLabels) {
				if (binLabel.clicked) {
					/// The user must click outside a bin.
					return;
				}
			}
			/// the rest is similar to the addition of new marker (see equivalent method in MarkerView.m)
			Mmarker *marker = (Mmarker*)enabledMarkerLabel.region;
			float position = [self sizeForX:self.mouseLocation.x];         			/// we convert the mouse position in base pairs
			float clickedPosition =  [self sizeForX:self.clickedPoint.x];      		/// we obtain the original clicked position in base pairs
			
			/// we check if we have room to add the new bin
			float safePosition = position < clickedPosition? clickedPosition - 0.13 : clickedPosition + 0.13;
			for(Bin *bin in marker.bins) {
				if(safePosition >= bin.start && safePosition <= bin.end) {
					return;
				}
			}
			NSError *error;
			draggedLabel = [enabledMarkerLabel labelWithNewBinByDraggingWithError:&error];
			if(error) {
				error = [NSError errorWithDescription:@"The bin could not be added because an error occurred in the database."
													suggestion:@"You may quit the application and try again"];
				[[NSAlert alertWithError:error] beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
				}];
			} else if(draggedLabel) {
				dashedLineLayer.hidden = YES;	/// it is better to hide the dashed line when the bin is created, to reduce visual clutter.
				[NSCursor.resizeLeftRightCursor set];
			}
		}
	}
}


- (void)labelIsDragged:(ViewLabel *)label {
	draggedLabel = label;
	if(label != self.enabledMarkerLabel) {
		/// We don't scroll while dragging this label, as it would be disturbing.
		[self autoscrollWithDraggedLabel:label];
	}
}


- (void)autoscrollWithDraggedLabel:(ViewLabel *)draggedLabel {
	NSRect labelFrame = draggedLabel.frame;
	NSRect clipRect = self.clipRect;
	if([draggedLabel respondsToSelector:@selector(clickedEdge)]) {
		RegionEdge clickedEdge = ((RegionLabel *)draggedLabel).clickedEdge;
		if(clickedEdge == betweenEdges) {
			if(labelFrame.size.width > clipRect.size.width)
				/// if a label is dragged (not resized) and is larger than what we show, we don't scroll.
				return;
		}
	} else if([draggedLabel respondsToSelector:@selector(dragHandleEndPosition)]) {
		float xPos = [(PeakLabel *)draggedLabel dragHandleEndPosition].x;
		labelFrame = NSMakeRect(xPos-3, 0, 6, 1);
	}
	
	[self scrollRectToVisible:labelFrame];
}


- (void)updateTrackingAreas {
	/// For performance, we avoid updating tracking areas too frequently, in particular during scrolling or zooming.
	/// Since macOS 13, this method is called at every step during scrolling
	/// But we need a timer to update the tracking areas when scrolling/zooming if finished
	if(updateTrackingAreasTimer.valid) {
		[updateTrackingAreasTimer invalidate];
	}
	updateTrackingAreasTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 
																target:self
															  selector:@selector(doneMoving)
															  userInfo:nil repeats:NO];
}


- (void)doneMoving {
	if(self.isMoving && self.autoScaleToHighestPeak) {
		[self scaleToHighestPeakWithAnimation:YES];
	}
	self.isMoving = NO;
	[self _updateTrackingAreas];
}


- (void)_updateTrackingAreas {
	[super updateTrackingAreas];  			  /// this updates the view's main tracking area, which occupies the visible rect
	
	[self updateLabelAreas];
	
	MarkerView *markerView = self.markerView;
	if(markerView && !markerView.isHidden) {
		[markerView updateTrackingAreas];
	}
}
	
	
-(void)updateLabelAreas {
	RegionLabel *enabledMarkerLabel = self.enabledMarkerLabel;
	if (enabledMarkerLabel) {
		[enabledMarkerLabel updateTrackingArea];
	} else {
		[self updateTrackingAreasOf:self.peakLabels];
	}
}



# pragma mark - others

- (void)dealloc {
	[self stopObservingSamples];
	for(NSString *keyPath in @[@"trace.peaks", @"trace.fragments", @"panel.markers"]) {
		[self removeObserver:self forKeyPath:keyPath];
	}
}


@end
