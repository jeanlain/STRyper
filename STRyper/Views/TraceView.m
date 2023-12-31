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
#include <sys/sysctl.h>

@interface TraceView ()

/// redefinition of properties that are readonly by other objects
@property (nonatomic) ChannelNumber channel;
@property (nonatomic, nullable) NSArray *binLabels;
@property (nonatomic, nullable) NSArray *peakLabels;
@property (nonatomic, nullable) NSArray *fragmentLabels;
@property (nonatomic) BOOL isResizing;


/// the label of marker whose bins are being edited. This can be set by the marker itself, but it should not be set arbitrarily
@property (nonatomic, weak) RegionLabel *enabledMarkerLabel;
																		
/// Used to animate a change in visibleRange. We use NSSize rather than BaseRange because the animator doesn't recognize the BaseRange struct.
@property (nonatomic) NSSize animatableRange;

/// Colors used to drawn offscale regions depending in the channel that presumably saturated the camera. These colors are derived from colorsForChannels
@property (nonatomic) NSArray<NSColor *> *colorForOffScaleScans;

/// Property that can be bound to the NSApp effective appearance. There is no ivar backing it it, the setter just tells the view to conform to the app's appearance.
@property (nonatomic) NSAppearance *viewAppearance;

/// Whether the traces should be redrawn (upon geometry change of change of other attributes).
@property (nonatomic) BOOL needsDisplayTraces;

/// Whether the layer(s) showing traces need to be laid out.
@property (nonatomic) BOOL needsLayoutTraceLayer;

/// The rectangle that is clipped by our superview (in our coordinates), subtracting the region masked by the vscale view.
@property (readonly, nonatomic) NSRect clipRect;

/// The width of the `clipRect` (faster to generate)
@property (readonly, nonatomic) float visibleWidth;

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

static BOOL appleSilicon;			/// whether the Mac running the application has an Apple SoC.
									/// We use it for drawing optimisations.

@implementation TraceView {
	
	float height;					/// a shortcut to the view's height (not used often. Could be removed)
	float maxReadLength;			/// the length (in base pairs) of the longest trace the view shows
	float viewLength;				/// It is either the maxReadLength or the max end size the user as set in the preferences, whichever is longer
	
	NSTimer *resizingTimer;			/// A timer that triggers to update tracking areas, and avoid updating them when the view is moving or resized
	
	CAShapeLayer *dashedLineLayer;	/// a layer showing a vertical dashed line at the mouse location that helps the user insert bins (note: we could use a single instance in a global variable for this layer, since only one dashed line should show at a time)
	
	float startPoint; 						/// (for dragging... not used)
	
	NSArray<Trace *> *visibleTraces;		/// the traces that are actually visible, depending on the channel to show
	
	NSArray *observedSamples;				/// The chromatograms we observe for certain keypaths.
	NSArray *observedSamplesForPanel;
	
	__weak RegionLabel *hoveredBinLabel;	/// the bin label being hovered, which we use to determine the cursor
	__weak PeakLabel *hoveredPeakLabel;		/// the peak label being hovered, which we may need to reposition
	
	BOOL showMarkerOnly;
	
	/**** ivars used for drawing traces **/
	/// We don't draw traces in the backing layer as we need to show bin and marker labels (which use layers) behind traces
	/// A single layer cannot hold the whole traces. If it's too large, drawing doesn't work (even if constrained to a small rectangle of the layer).
	/// A CATiledLayer can be very large, but doesn't appear suited to this task.
	/// We position and draw contiguous layers during scrolling (similar to "responsive scrolling, which appears disabled in macOS 14).
	
	CALayer *traceLayerParent; 		/// The parent layer of the trace layers, sorted from left to right along the X axis in its sublayers array
	__weak CALayer *traceLayerFillingClipRect;		/// The trace layer that fits in the `clipRect`, if any.
													/// We use this information to avoid repositioning this layer when not required
	
	NSMutableSet<CALayer *> *traceLayers; /// The currently unused layers that are not in the layer tree.
	
	NSTimer *overdrawTimer;		/// Used to trigger the drawing of traces outside the visible rectangle, to anticipate scrolling.
	float drawnRangeStart;		/// The position of the leading edge of the leftmost trace layer (in view coordinates), which we store to avoid computations
	float drawnRangeEnd;		/// The position of the trailing edge of the rightmost trace layer
	BOOL traceLayerCanAnimateBoundChange;
	
}

static float defaultTraceLayerWidth = 512; /// Default width of a trace layer in points

@synthesize markerLabels = _markerLabels, backgroundLayer = _backgroundLayer, rulerView = _rulerView, markerView = _markerView;

#pragma mark - initialization methods

+ (void)initialize {
	
	gLabelFontStyle = @{NSFontAttributeName: [NSFont labelFontOfSize:8.0], NSForegroundColorAttributeName: NSColor.secondaryLabelColor};
	
	animatableKeys = @[NSStringFromSelector(@selector(topFluoLevel)),
					   NSStringFromSelector(@selector(animatableRange)),
					   NSStringFromSelector(@selector(vScale))];

	/// We determine if the SoC is from Apple by reading the CPU brand.
	/// There may be a better way by reading the architecture.
	size_t size = 100;		/// To make sure that we can read the whole CPU name.
	char string[size];
	sysctlbyname("machdep.cpu.brand_string", &string, &size, nil, 0);
	appleSilicon = strncmp(string, "Apple", 5) == 0;
	
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
	
	traceLayers = NSMutableSet.new;
	traceLayerParent = CALayer.new;
	traceLayerParent.delegate = self;
	traceLayerParent.zPosition = -0.4;  /// To ensure traces show behind fragment labels, which cannot have a positive zPosition.
	traceLayerParent.anchorPoint = CGPointMake(0, 0);
	[self.layer addSublayer:traceLayerParent];
	
	/// The views' background is white
	self.layer.backgroundColor = NSColor.whiteColor.CGColor;
	self.layer.opaque = YES;
	
	/// Since -updateLayer or -drawRect are not called on needsDisplay (which is problematic to update the view appearance)
	/// we simply never redraw the view's layer
	self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;
	
	[self setBoundsOrigin:NSMakePoint(0, -0.5)];
	
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
		
	_showDisabledBins = YES;
	_showRawData = NO;
	_showOffscaleRegions = YES;
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


- (CALayer *)backgroundLayer {
	if(!_backgroundLayer) {
		_backgroundLayer = self.layer;
		_backgroundLayer.actions = @{kCAOnOrderIn: NSNull.null, kCAOnOrderOut: NSNull.null,
									 NSStringFromSelector(@selector(sublayers)): NSNull.null,
									 NSStringFromSelector(@selector(position)): NSNull.null};
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

- (void)loadTraces:(NSArray<Trace *> *)traces {
	[self loadTraces:traces marker:nil];
}


- (void)loadSample:(Chromatogram *)sample {
	[self loadTraces:sample.traces.allObjects marker:nil];
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
}


- (void)loadMarker:(Mmarker *)marker {
	[self loadTraces:nil marker:marker];
}

/// loads the specified traces and the marker
- (void)loadTraces:(nullable NSArray<Trace *> *)traces marker:(nullable Mmarker *)marker {
	
	/// We set the hScale to -1 to signify that our geometry is reset and not final. This is to prevent our range from being modified in resizeWithOldSuperViewSize: before prepareForDisplay: (the latter sets our hScale)
	_hScale = -1.0;
	if(overdrawTimer.valid) {
		[overdrawTimer invalidate];
	}
	
	if(resizingTimer.valid) {
		[resizingTimer invalidate];
	}
	
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
	showMarkerOnly = traces.count == 0;
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


- (void)prepareForReuse {
	[super prepareForReuse];
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
	if(self.showOffscaleRegions && (visibleTraces.count == 1 || self.channel == -1)) {
		/// We redraw as we don't show off-scale regions when a marker label is enabled (to avoid interference with its rectangle and its bins).
		self.needsDisplayTraces = YES;
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
	NSArray *labels = [self.panelLabels arrayByAddingObjectsFromArray:self.fragmentLabels];
	if(hoveredPeakLabel) {
		labels = [labels arrayByAddingObject:hoveredPeakLabel];
	}
	return labels;
}


- (void)setNeedsLayoutFragmentLabels:(BOOL)needsLayoutFragmentLabels {
	_needsLayoutFragmentLabels = needsLayoutFragmentLabels;
	if(needsLayoutFragmentLabels) {
		self.needsLayout = YES;
	}
}



-(void)layout {
	if(self.needsLayoutTraceLayer) {
		[self repositionTraceLayer];
		self.needsLayoutTraceLayer = NO;
	}
	
	if(self.needsLayoutFragmentLabels && !self.needsLayoutLabels && self.hScale >=0) {
		/// we don't need to reposition fragment labels here if all labels will be repositioned anyway (in super)
		/// This should be the case when the vertical scale is changed by the view geometry has not
		for(FragmentLabel *label in self.fragmentLabels) {
			label.animated = NO;
			[label reposition];
			label.animated = YES;
		}
	}
	[super layout];
	self.needsLayoutFragmentLabels = NO;
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if(context == sampleSizingChangedContext) {
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
			self.needsDisplayTraces = YES;
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

- (BOOL)wantsUpdateLayer {
	return YES;  /// Since we don't update the view's layer, this may not change anything.
}


- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	if(layer.superlayer == traceLayerParent) {
		if(traceLayerCanAnimateBoundChange) {
			return nil;
		}
		return NSNull.null;
	} else if(layer == traceLayerParent) {
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
	_needsDisplayTraces = display;
	if(display) {
		/// We traces needs to be redrawn, we draw a layer that fits the visible rectangle return by clipRect
		if(!traceLayerFillingClipRect) {
			self.needsLayoutTraceLayer = YES;
		} else {
			/// If a layer is already in place, we don't need to position it, just mark it for redisplay.
			[traceLayerFillingClipRect setNeedsDisplay];
			/// but we need to remove any other trace layer
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
			}
		}
	}
}


- (void)setNeedsLayoutTraceLayer:(BOOL)needsLayoutTraceLayer {
	_needsLayoutTraceLayer = needsLayoutTraceLayer;
	if(needsLayoutTraceLayer) {
		/// We layout trace layers in -layout rather than -layoutSublayersOfLayer: 
		/// because the latter is not called at appropriate times wrt changes in view geometry.
		/// Traces should be adjust perfectly in sync with change in view geometry, in particular during zooming
		self.needsLayout = YES;
	}
}


-(void)repositionTraceLayer {
	NSRect clipRect = self.clipRect;
	float visibleStart = clipRect.origin.x;
	float visibleEnd = NSMaxX(clipRect);
	
	if(_needsDisplayTraces || visibleEnd < drawnRangeStart || visibleStart > drawnRangeEnd) {
		/// If traces needs to ne redrawn or if the clipRect does not intersect what is drawn, we place a layer in the clipRect and remove others
		traceLayerFillingClipRect = [self positionTraceLayerFromStart:visibleStart toEnd:visibleEnd clipRect:clipRect clearOtherLayers:YES];
		return;
	}
	
	if(drawnRangeStart > 0 && visibleStart < drawnRangeStart+1)  {
		/// If a region that is not drawn has become visible at the left, we place a layer there.
		/// The 1-point margin ensure that a layer will be placed if this method is called when there is nothing drawn at the left of the clipRect
		/// This will draw traces there to anticipate scrolling (overdraw).
		float layerStart = drawnRangeStart - defaultTraceLayerWidth;
		if(layerStart > visibleStart) {
			layerStart = visibleStart;
		}
		[self positionTraceLayerFromStart:layerStart toEnd:drawnRangeStart clipRect:clipRect clearOtherLayers:NO];
	}
		
	if (drawnRangeEnd < visibleEnd+1) {
		/// If some area has become visible (with a 1-point margin) at the right, we place a layer there.
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
		long count = sublayers.count;
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
	traceLayer.bounds = layerBounds; /// This ensure that the coordinates in the layer are the same as those in the view
	traceLayer.position = layerBounds.origin;
	[traceLayer setNeedsDisplay]; /// In case the bounds haven't changed, we mark the positioned layer for display
								  
	return traceLayer;
}


-(void)overdraw {
	if(!_needsDisplayTraces) {
		self.needsLayoutTraceLayer = YES;
		/// This should place layers at the end and right of the clipRect if they aren't any
	}
}


- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
	if(layer.superlayer == traceLayerParent) {
		if(overdrawTimer.valid) {
			[overdrawTimer invalidate];
		}
		overdrawTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self
															 selector:@selector(overdraw) userInfo:nil repeats:NO];
		[self drawTracesInRect:layer.bounds context:ctx];
		self.needsDisplayTraces = NO;
	}
}



/// Draws trace-related elements in the view.
/// - Parameters:
///   - dirtyRect: The rectangle in which to draw, which is the same in view coordinates and layer coordinate.
///   We don't use the clipping bounding box of the context, as it may be costly to query, apparently.
///   - ctx: The graphics context in which we draw.
- (void)drawTracesInRect:(NSRect) dirtyRect context:(CGContextRef) ctx {
	
	if(visibleTraces.count == 0) {
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
	const float *sizes = sample.sizes.bytes;
	long nScans = sample.sizes.length / sizeof(float);
	if(nScans == 0) {
		return;
	}
	
	/// We show offscale regions (with vertical rectangles)
	/// We don't drawn them if we have traces from several samples and if a marker label is enabled, 
	/// as these regions can mask the edges  of this label or its bin labels
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
				CGContextSetFillColorWithColor(ctx, color.CGColor);
				float x1 = (regionStart - sampleStartSize) * hScale;
				float x2 = (regionEnd - sampleStartSize) * hScale;
				float scanWidth = (x2-x1)/region.regionWidth;
				/// we place the rectangle at half a scan to the left, so that it is centered around the saturated scans
				CGContextFillRect(ctx, CGRectMake(x1 - scanWidth/2, 0, x2-x1, NSMaxY(self.bounds)));
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
		
		NSColor *strokeColor = self.colorsForChannels[traceToDraw.channel];
		CGContextSetStrokeColorWithColor(ctx, strokeColor.CGColor);
		
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
		self.isMoving = YES;
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
			self.vScale = NSMaxY(self.bounds)/_topFluoLevel;
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
			self.vScale = NSMaxY(self.bounds)/_topFluoLevel;
		}
	}
}


- (void)setVScale:(float)scale {
	if (scale != _vScale) {
		_vScale = scale;
		self.needsDisplayTraces = YES;
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
		[clipView scrollToPoint:NSMakePoint(newVisibleOrigin - self.leftInset, 0)];
		[self.enclosingScrollView reflectScrolledClipView:clipView];
		traceLayerFillingClipRect = nil;  /// The layer showing traces no longer fits the visible rectangle
		self.needsLayoutTraceLayer = YES; /// We need to position trace layers during scrolling.
		
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
	
	/// we change ivars related to geometry to signify the the view is not in its final state.
	/// We don't use the setters as we don't want the view to actually change the geometry of the view to match these dummy values
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
	
	self.needsDisplayTraces = YES;
	
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


- (BOOL)clipsToBounds {
	return YES;
}


- (void)setLeftInset:(float)leftInset {
	_leftInset = leftInset;
	NSScrollView *scrollView = self.enclosingScrollView;
	NSEdgeInsets insets = scrollView.contentInsets;
	insets.left = leftInset;
	scrollView.contentInsets = insets;
}


- (void)setBoundsOrigin:(NSPoint)newOrigin {
	/// we set our bounds origin to adapt to the presence of vScaleView, which overlaps us.
	/// our bounds x origin must be reflected by the top ruler view and the marker view, or else graduation and markers will not show at the correct position relative to the traces
	[super setBoundsOrigin:newOrigin];
	[self.markerView setBoundsOrigin:NSMakePoint(newOrigin.x,0)];
	[self.rulerView setBoundsOrigin:NSMakePoint(newOrigin.x, 0)];
	NSPoint point = [self.vScaleView convertPoint:NSMakePoint(0, 0) fromView:self];
	[self.vScaleView setBoundsOrigin:NSMakePoint(0, -point.y)];
	traceLayerParent.bounds = CGRectMake(newOrigin.x, newOrigin.y, 10, 10); /// The size is not important
	traceLayerParent.frame = traceLayerParent.bounds;
	self.needsLayoutLabels = YES;
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
	if(self.hScale <= 0.0) {
		return;  				/// we do not react when our visible range is not yet set
	}
	
	NSSize newSize = self.superview.bounds.size;
	
	if(newSize.height != oldSize.height) {
		[self fitVertically];
	}
	
	if(newSize.width != oldSize.width) {
		self.hScale = self.visibleWidth / _visibleRange.len;;
		self.visibleOrigin = (_visibleRange.start - _sampleStartSize) * _hScale;
	}
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
		if(!self.needsLayoutLabels) {
			/// all labels may have already been repositioned before -layout (if the view was resized with animation)
			self.needsLayoutFragmentLabels = NO;
		}
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


- (void)setFrameSize:(NSSize)newSize {
	[super setFrameSize:newSize];
	if(!self.needsLayoutLabels && traceLayerFillingClipRect) {
		/// in this case, the labels have been repositioned immediately, which means the view is resized with animation
		/// we also reposition the trace layer now (in layout, it will be too late to follow the animation)
		traceLayerCanAnimateBoundChange = YES;
		_needsDisplayTraces = YES;
		[self repositionTraceLayer];
		traceLayerCanAnimateBoundChange = NO;
	} else {
		self.needsDisplayTraces = YES;
		self.needsLayoutTraceLayer = YES;
	}
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
	float hScale = self.hScale;
	if(hScale < 0) {
		hScale = 0;
	}
	return NSMakeSize(viewLength * hScale - self.bounds.origin.x, height);
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
			if(self.showPeakTooltips) {
				[self removeAllToolTips];
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
		/// offScale regions are drawn together with traces, so:
		self.needsDisplayTraces = YES;
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
	self.needsDisplayTraces = YES;
}


- (void)setMaintainPeakHeights:(BOOL)maintainPeakHeights {
	_maintainPeakHeights = maintainPeakHeights;
	if(self.autoScaleToHighestPeak) {
		[self scaleToHighestPeakWithAnimation:YES];
	}
	self.needsLayoutFragmentLabels = YES; /// because peak heights may change
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
	self.needsDisplayTraces = YES;
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
		self.needsDisplayTraces = YES;
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



#pragma mark - reacting to mouse and key events

- (BOOL)acceptsFirstResponder {
	return YES;
}


- (BOOL)resignFirstResponder {
	self.rulerView.currentPosition = -10000;
	for (ViewLabel *label in self.viewLabels){
		if([label respondsToSelector:@selector(attachedPopover)]) {
			if([(RegionLabel *)label attachedPopover] == nil) {
				/// if the label has a popover, this method is likely call because the popover is spawn
				/// in this case we don't dehighlight the label. We only do it if it has no popover attached.
				label.highlighted = NO;
			}
		} else {
			label.highlighted = NO;
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
				/// in which case a force click isn't need. Or they may be editing the marker offset, in which case no bin should be selectable
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
			/// We add the peak to the menu item.
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
	[self repositionLabels:self.peakLabels allowAnimation:NO];
	for(PeakLabel *peakLabel in self.peakLabels) {
		[peakLabel updateTrackingArea];
		[peakLabel mouseDownInView];
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
	[super mouseDown:theEvent];
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
}


- (void)autoscrollWithDraggedLabel:(ViewLabel *)draggedLabel {
	/// we autoscroll if the mouse is dragged over the rightmost button on the left (the "+"' button), or the button on the right
	
	NSRect frame = draggedLabel.frame;
	if(!NSPointInRect(self.mouseLocation, frame)) {
		return;
	}
	NSRect bounds = self.bounds;
	NSRect rect = self.visibleRect;
	RegionEdge clickedEdge = noEdge;
	if([draggedLabel isKindOfClass:RegionLabel.class]) {
		clickedEdge = ((RegionLabel *)draggedLabel).clickedEdge;
		if(clickedEdge == betweenEdges && (frame.size.width >= rect.size.width || draggedLabel == self.enabledMarkerLabel)) {
			/// if a label is dragged (not resized) and is larger than what we show, we don't scroll.
			/// We don't scroll either it it is the marker label, as scrolling in this situation is disturbing. 
			return;
		}
	}
	
	float leftLimit = rect.origin.x;
	float rightLimit = NSMaxX(rect);
	
	/// if the mouse goes beyond the left limit, we scroll to the right, hence reveal the left
	float delta = NSMinX(frame) - leftLimit;
	
	float visibleOrigin = self.visibleOrigin;
	float newOrigin = -1000;
	
	if(delta < 0 && clickedEdge != rightEdge) {
		newOrigin = visibleOrigin + delta;
	} else if(clickedEdge != leftEdge) {
		/// if the mouse goes beyond the right limit, we scroll to the opposite direction
		delta = NSMaxX(frame) - rightLimit;
		if(delta > 0) {
			newOrigin = visibleOrigin + delta;
		}
	}
	if(newOrigin > -1000) {
		if(newOrigin < bounds.origin.x) {
			newOrigin =  bounds.origin.x;
		} else {
			float maxOrigin = NSMaxX(bounds) - rect.size.width;
			if(newOrigin > maxOrigin) {
				newOrigin = maxOrigin;
			}
		}
		BaseRange newRange = self.visibleRange;
		newRange.start = newOrigin / self.hScale + self.sampleStartSize;
		self.visibleRange = newRange;
	}

}


- (void)updateTrackingAreas {
	/// For performance, we avoid updating tracking areas too frequently, in particular during scrolling or zooming.
	/// In particular since macOS 13, this method is called at every step during scrolling
	/// But we need a timer to update the tracking areas when scrolling/zooming if finished
	if(resizingTimer.valid) {
		[resizingTimer invalidate];
	}
	resizingTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(doneMoving) userInfo:nil repeats:NO];
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
