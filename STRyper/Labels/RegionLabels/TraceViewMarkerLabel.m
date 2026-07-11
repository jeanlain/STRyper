//
//  TraceViewMarkerLabel.m
//  STRyper
//
//  Created by Jean Peccoud on 25/03/2023.
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


#import "TraceViewMarkerLabel.h"
#import "TraceView.h"
#import "Bin.h"
#import "BinLabel.h"
#import "Mmarker.h"
#import "MarkerLabel.h"
#import "NSArray+NSArrayAdditions.h"
#import "MarkerView.h"

@interface TraceViewMarkerLabel ()

/// Layers used to symbolize inner and outer limit ivars (see below).
/// We use properties to generate the layers only when needed, as the show only when the label is dragged.
@property (nonatomic) CALayer *innerLayer;
@property (nonatomic) CALayer *outerLayer;
@property (nonatomic) CALayer *anchorLayer; /// Symbolizes `anchorPos`

@end


@implementation TraceViewMarkerLabel {
	
	/// When the user drags the label or its edge, we define limits for both edges
	/// "outer" limits represent the maximum width the label can take. This ensure bins remain in the marker's range.
	/// Inner limits represent the minimum width
	/// The width is constrained as we do not allow shrinking the binset to an arbitrary level (or to set an offset that is too extreme).
	CGFloat outerLeftLimit;
	CGFloat outerRightLimit;
	CGFloat innerLeftLimit;
	CGFloat innerRightLimit;
	
	/// The position (in base pairs) that does not move when the label is resized and its represented by an vertical line (the anchor) when the label is dragged.
	CGFloat anchorPos; /// It is computed in the coordinates of the marker represented by the label, given its offset.
	CGFloat anchorPosInView;	/// The same, in view coordinates (still in base pairs).

	
	CALayer *anchorSymbolLayer;		/// A symbol that conveys the notion that the anchor won't move during resizing.
	Genotype *observedGenotype; 	/// The genotype we observe to react to a change of its offset.
	BOOL needsUpdateBinLabels;
	BOOL offsetAffectsAlleles;		/// Whether the offset of the label changes allele position (rather than bin position)
}

# pragma mark - attributes and appearance



- (BOOL)isMarkerLabel {
	return YES;
}


- (CALayer *)_layer {
	return layer;
}


static void * const markerBinsChangedContext = (void*)&markerBinsChangedContext;

/// To be notified when the offset of the marker we represent changes.
static void * const viewTraceChangedContext = (void*)&viewTraceChangedContext;
static void * const genotypeOffsetChangedContext = (void*)&genotypeOffsetChangedContext;


- (instancetype)init {
	self = [super init];
	if (self) {
		layer.anchorPoint = CGPointZero;
		
		/// Our layer represents the range of our region and is a light pink rectangle with black borders
		layer.zPosition = -1.0;  				/// this makes sure we show behind bin labels
		
		/// This type is disabled by default
		_enabled = NO;
	}
	return self;
}


- (void)setView:(TraceView *)view {
	if(self.view) {
		[self.view removeObserver:self forKeyPath:@"trace"];
		[self.view removeObserver:self forKeyPath:@"loadedGenotypes"];
	}
	super.view = view;
	if(layer && view) {
		/// We get notified if the view has loaded a new trace, as the offset of our marker depends on the sample shown.
		[view addObserver:self forKeyPath:@"trace"
					options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					context:viewTraceChangedContext];
		
		[view addObserver:self forKeyPath:@"loadedGenotypes"
					options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					context:viewTraceChangedContext];
		
		layer.borderColor = view.regionLabelEdgeColor;
		[view.backgroundLayer addSublayer:layer];
		for(BinLabel *binLabel in self.binLabels) {
			binLabel.view = view;
		}
	}
}


- (void)setRegion:(__kindof Region *)region {
	if(self.region) {
		[self.region removeObserver:self forKeyPath:@"bins"];
	}
	super.region = region;
	if(region) {
		[region addObserver:self forKeyPath:@"bins"
					options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					context:markerBinsChangedContext];
	}
	[self observeGenotype];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context == markerBinsChangedContext) {
		needsUpdateBinLabels = YES;
		self.needsUpdateAppearance = YES;
	} else if(context == viewTraceChangedContext) {
		offsetAffectsAlleles = self.view.loadedGenotypes.count > 0;
		[self observeGenotype];
	} else if(context == genotypeOffsetChangedContext) {
		if(self.editState != editStateBinSet && !(self.editState == editStateBins && offsetAffectsAlleles)) {
			[self applyGenotypeOffset];
		}
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


-(void)applyGenotypeOffset {
	MarkerOffset offset = observedGenotype.offset;
	if(offsetAffectsAlleles) {
		offset.intercept = -offset.intercept/offset.slope;
		offset.slope = 1/offset.slope;
	}
	self.offset = offset;
}

- (void)observeGenotype {
	Genotype *genotype;
	Chromatogram *sample = self.view.trace.chromatogram;
	if(sample) {
		genotype = [sample genotypeForMarker:self.region]; /// nil if there is no sample shown
	} else {
		genotype = self.view.loadedGenotypes.firstObject;
	}
	if(self.editState >= editStateOffset) {
		/// we exit the editing.
		self.editState = editStateNil;
	}
	if(genotype != observedGenotype) {
		if(observedGenotype) {
			[observedGenotype removeObserver:self forKeyPath:@"offsetData"];
		}
		observedGenotype = genotype;
		if(observedGenotype) {
			[observedGenotype addObserver:self forKeyPath:@"offsetData"
								  options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
								  context:genotypeOffsetChangedContext];
		} else {
			self.offset = MarkerOffsetNone;
		}
	}
}



-(void) removeFromView {
	[_anchorLayer removeFromSuperlayer];
	[_innerLayer removeFromSuperlayer];
	[_outerLayer removeFromSuperlayer];
	[self.view.undoManager removeAllActionsWithTarget:self];
	for(BinLabel *binLabel in self.binLabels) {
		[binLabel removeFromView];
	}
	[super removeFromView];
}


- (void)setHovered:(BOOL)hovered {
	/// overridden as our appearance does not change when hovered (which is the default)
	if (self.hovered != hovered) {
		_hovered = hovered;
		[self.view labelDidChangeHoveredState:self];
	}
}


- (void)updateAppearance {
	if(needsUpdateBinLabels) {
		[self updateBinLabels];
	}
	
	/// The label has no background color when not enabled.
	layer.backgroundColor = self.enabled? self.view.traceViewMarkerLabelBackgroundColor : nil;
	if(!self.highlighted || !self.enabled) {
		_anchorLayer.hidden = YES;
	}
	[super updateAppearance];
}


- (void)setEnabled:(BOOL) state {
	if(self.enabled != state) {
		super.enabled = state;
		anchorPos = -1;
	}
}


- (void)setHidden:(BOOL)hidden {
	if(self.hidden != hidden) {
		super.hidden = hidden;
		for (BinLabel *binLabel in self.binLabels) {
			/// We update the appearance of bin labels as their band layers are not sublayers of the label's layer.
			binLabel.needsUpdateAppearance = YES;
		}
		if(!hidden) {
			self.view.allowsAnimations = NO;
			/// As bins label become visible, they need repositioning (without animation)
			[self.view labelNeedsRepositioning:self];
		}
	}
}


- (BOOL)deHighlightAutomatically {
	/// This type of label is highlighted to move bins or adjust offsets, and all labels representing the marker are highlighted for this operation.
	/// Therefore, they must not de-highlight automatically.
	return NO;
}


- (NSMenu *)menu {
	/// The menu is that which appear when the user right-click within the marker range.
	NSMenu *menu = NSMenu.new;
	RegionLabel *targetLabel;
	for(RegionLabel *label in self.view.markerView.markerLabels) {
		if (label.region == self.region) {
			targetLabel = label;
			break;
		}
	}
	NSMenuItem *item;
	Mmarker *marker = self.region;
	NSString *title = [NSString stringWithFormat:@"Generate Bins for '%@'", marker.name];
	item = [[NSMenuItem alloc] initWithTitle:title action:@selector(spawnAddBinsPopover:) keyEquivalent:@""];
	item.target = targetLabel;
	item.image = [NSImage imageNamed:ACImageNameBinset];
	[menu addItem:item];

	item = [[NSMenuItem alloc] initWithTitle:@"Edit Bins Manually" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
	item.target = self;
	item.tag = editStateBins;
	item.image = [NSImage imageNamed:ACImageNameEditBins];
	[menu addItem:item];
	
	item = [[NSMenuItem alloc] initWithTitle:@"Move all Bins" action:@selector(setEditStateFromMenuItem:) keyEquivalent:@""];
	item.target = self;
	item.tag = editStateBinSet;
	item.image = [NSImage imageNamed:ACImageNameMoveBins];
	[menu addItem:item];
	
	return menu;
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if(menuItem.action == @selector(setEditStateFromMenuItem:)) {
		if(menuItem.tag == self.editState || (menuItem.tag == editStateBinSet &&
		   ((Mmarker*)self.region).bins.count == 0)) {
			menuItem.hidden = YES;
			return NO;
		}
	}
	menuItem.hidden = NO;
	return YES;
}


- (void)setClicked:(BOOL)clicked {
	/// overridden to show our anchorLayer when appropriate
	if(clicked != self.clicked) {
		super.clicked = clicked;
		if(self.highlighted && self.clickedEdge == betweenEdges) {
			MarkerOffset offset = self.offset;
			TraceView *view = self.view;
			CGFloat clickedPosition = [view sizeForX:view.clickedPoint.x];
			CGFloat clickedPositionInMarker = (clickedPosition - offset.intercept)/offset.slope;
			if(clickedPositionInMarker > self.start +1.0 && clickedPositionInMarker < self.end -1.0) {
				anchorPos = clickedPositionInMarker;
				anchorPosInView = clickedPosition;
				self.anchorLayer.hidden = NO;
				/// Since the anchor layer must be repositioned with the label whenever it shows
				/// we just reposition the whole label rather than setting `needsUpdateAppearance`.
			} else {
				anchorPos = anchorPosInView = -1.0;
			}
			[self.view labelNeedsRepositioning:self];
		}
	}
}


- (void)updateColors {
	
	static NSImage *anchorImage;
	if(!anchorImage) {
		anchorImage = [NSImage imageNamed:ACImageNameAnchor];
	}
	
	TraceView *view = self.view;
	layer.borderColor = view.regionLabelEdgeColor;
	layer.backgroundColor = self.enabled? view.traceViewMarkerLabelBackgroundColor : nil;
	if(_outerLayer) {
		_outerLayer.backgroundColor = view.traceViewMarkerLabelAllowedRangeColor;
	}
	if(_innerLayer) {
		_innerLayer.backgroundColor = view.traceViewMarkerLabelInnerLayerColor;
	}
	anchorSymbolLayer.contents = (__bridge id _Nullable)([anchorImage CGImageForProposedRect:nil context:nil hints:nil]);
	
	for(BinLabel *binLabel in self.binLabels) {
		[binLabel updateColors];
	}
}

# pragma mark -  actions / dragging


-(void)setEditStateFromMenuItem:(NSMenuItem *)sender {
	self.editState = sender.tag;
}



- (CALayer *)innerLayer {
	if(!_innerLayer) {
		TraceView *view = self.view;
		_innerLayer = CALayer.new;
		_innerLayer.borderWidth = 1.0;
		_innerLayer.borderColor = NSColor.grayColor.CGColor;
		_innerLayer.backgroundColor = self.view.traceViewMarkerLabelInnerLayerColor;
		_innerLayer.zPosition = -0.5;		/// otherwise, this could be hidden by bins
		_innerLayer.delegate = self;
		[view.backgroundLayer addSublayer:_innerLayer];
	}
	return _innerLayer;
}


- (CALayer *)outerLayer {
	if(!_outerLayer) {
		TraceView *view = self.view;
		_outerLayer = CALayer.new;
		_outerLayer.backgroundColor = view.traceViewMarkerLabelAllowedRangeColor;
		_outerLayer.opaque = YES;
		_outerLayer.zPosition = -1;
		_outerLayer.delegate = self;
		[view.backgroundLayer insertSublayer:_outerLayer below:layer];

	}
	return _outerLayer;
}


- (CALayer *)anchorLayer {
	if(!_anchorLayer) {
		_anchorLayer = CALayer.new;
		_anchorLayer.delegate = self;
		_anchorLayer.backgroundColor = NSColor.redColor.CGColor;
		_anchorLayer.anchorPoint = CGPointMake(1.0, 0.0);
		_anchorLayer.zPosition = 10.0;		/// this layer shows on top
		_anchorLayer.delegate = self;
		anchorSymbolLayer = CALayer.new;
		anchorSymbolLayer.delegate = self;
		anchorSymbolLayer.bounds = CGRectMake(0.0, 0.0, 15.0, 14.0);
		[_anchorLayer addSublayer:anchorSymbolLayer];
		TraceView *view = self.view;
		[view.backgroundLayer addSublayer:_anchorLayer];
		
		/// Because the anchorSymbolLayer is an image that depends on the app appearance,
		/// it must be set during updateColors to have the correct appearance.
		view.needsUpdateLabelColors = YES;
	}
	return _anchorLayer;
}

/// Overridden as the label does not get highlighted by a click. 
- (void)mouseDownInView {
	if(self.enabled) {
		if(!NSPointInRect(self.view.clickedPoint, self.frame)) {
			/// if the user has clicked outside our frame on the view, we end the editing of all labels showing our marker
			self.region.editState = editStateNil;
			self.clicked = NO;
		} else {
			self.clicked = YES;
		}
	}
}



- (void)rightMouseDownInView {
	/// We don't react to these events
}


- (void)mouseUpInView {
	/// We don't get highlighted by clicks
	if(self.enabled) {
		self.clicked = NO;
	}
}



- (void)setEditState:(EditState)editState {
	if(editState == self.editState) {
		return;
	}
	
	if(editState == editStateBinSet || (editState == editStateBins && offsetAffectsAlleles)) {
		/// if we enter this edit state, we make as if the marker had no offset (otherwise, moving bins would not be intuitive).
		self.offset = MarkerOffsetNone;
	}
	
	if(self.editState == editStateBinSet || (self.editState == editStateBins && offsetAffectsAlleles)) {
		/// if we exit the "binset" edit stage, we get back the offset of the genotype at our marker
		[self applyGenotypeOffset];
	}
	
	if(editState == editStateOffset && self.view.loadedGenotypes.count > 0) {
		NSInteger offsetCount = 0;
		MarkerOffset refOffset = MarkerOffsetNone;
		for(Genotype *genotype in self.view.loadedGenotypes) {
			MarkerOffset offset = genotype.offset;
			if((offset.intercept != refOffset.intercept || offset.slope != refOffset.slope) && (offset.intercept != 0.0f && offset.slope != 1.0f)) {
				refOffset = offset;
				offsetCount++;
				if(offsetCount > 1) {
					break;
				}
			}
		}
		
		if(offsetCount > 1) {
			NSAlert *alert = NSAlert.new;
			alert.messageText = @"The selected genotypes have different offsets for the marker.";
			alert.informativeText = @"If you proceed, these genotypes will get the same offset.";
			[alert addButtonWithTitle:@"Adjust Offset"];
			[alert addButtonWithTitle:@"Cancel"];
			NSModalResponse response = [alert runModal];
			if(response != NSAlertFirstButtonReturn) {
				self.region.editState = editStateNil;
				return;
			}
		}
		[self observeGenotype];
	}
	super.editState = editState;
	
	BOOL binEnabledState = NO;
	if(editState == editStateNil) {
		self.enabled = NO;
	} else if(editState == editStateBins) {
		self.enabled = YES;
		self.highlighted = NO;		/// When the user edits bins individually, the marker label behind bins (this label) is not highlighted
									/// it should not show its border and should not be resizable nor draggable
									/// it's only purpose is to show where bins can be added and to set a cursor when hovered to denote that
		binEnabledState = YES;
	} else {
		self.highlighted = YES;
	}
	
	for(BinLabel *binLabel in self.binLabels) {
		binLabel.enabled = binEnabledState;
	}
}


- (void)setLimitsForEdge:(RegionEdge)edge {
	float start = self.start;
	float end = self.end;
	Mmarker *marker = self.region;
	if((edge == leftEdge || edge == rightEdge)) {
		/// when the anchor is close to an edge, we place it at the edge that is  not dragged
		if(anchorPos < start + 1 || anchorPos > end -1)  {
			anchorPos = edge == leftEdge? end : start;
		}
		
		float slope = self.offset.slope;
		float intercept = self.offset.intercept;

		CGFloat anchorViewPos = anchorPos*slope + intercept;
		if(self.editState == editStateBinSet) {
			/// When the user moves the bin set, the bin widths are preserved.
			/// The limits must ensure that bins remain within the marker range and don't overlap.
			NSArray *sortedBins = marker.sortedBins;
			Bin *firstBin = sortedBins.firstObject;
			Bin *lastBin = sortedBins.lastObject;
			float firstBinPos = (firstBin.start + firstBin.end)/2;
			float lastBinPos = (lastBin.start + lastBin.end)/2;
			float firstBinWidth = (firstBin.end - firstBin.start);
			float lastBinWidth = (lastBin.end - lastBin.start);
			float firstBinAllowedPos = marker.start + 0.1f + firstBinWidth * 0.5f;	/// we leave a 0.1 bp margin to make sure the bins won't go out of range
			float lastBinAllowedPos = marker.end - 0.1f - lastBinWidth * 0.5f;
			
			/// We specify outer limits to prevent bins from being pushed out of the marker range when the label is expanded.
			if(anchorPos > firstBinPos) {
				outerLeftLimit = anchorPos - (anchorPos - start) * (anchorPos - firstBinAllowedPos) / (anchorPos - firstBinPos);
			} else {
				outerLeftLimit = 0;
			}
			
			if(anchorPos < lastBinPos) {
				outerRightLimit = anchorPos + (end - anchorPos) * (lastBinAllowedPos - anchorPos) / (lastBinPos - anchorPos);;
			} else {
				outerRightLimit = MAX_TRACE_LENGTH;
			}
			
			innerLeftLimit = anchorPos;
			innerRightLimit = anchorPos;
			
			/// Shrinking the label may push the outer part of first or last bin out of the marker range. We need to place limits to prevent that.
			if(anchorPos < firstBinAllowedPos) {
				innerRightLimit = anchorPos + (firstBinAllowedPos - anchorPos) * (end - anchorPos) / (firstBinPos - anchorPos);
			}
			
			if(anchorPos > lastBinAllowedPos) {
				innerLeftLimit = anchorPos - (anchorPos - lastBinAllowedPos) * (anchorPos - start) / (anchorPos - lastBinPos);
			}
			
			/// We must also prevent bins from overlapping when the marker is shrunk.
			float allowedShrinkRatio = self.maxShrinkRatio;
			float innerLeftLimitForRatio = anchorPos - allowedShrinkRatio*(anchorPos - start);
			float innerRightLimitForRatio = anchorPos - allowedShrinkRatio*(anchorPos - end);
			
			if(innerLeftLimit > innerLeftLimitForRatio) {
				innerLeftLimit = innerLeftLimitForRatio;
			}
			
			if(innerRightLimit < innerRightLimitForRatio) {
				innerRightLimit = innerRightLimitForRatio;
			}
		
		} else {
			/// Here the user is about to modify the marker offset.
			/// we determine allowed limits for the edge so that the slope does not go beyond limit
			/// When the offset affects allele, the limits are different, but results in the same effect limits for the genotype offset
			float maxSlope = offsetAffectsAlleles? 1/minOffsetSlope : maxOffsetSlope;
			float minSlope = offsetAffectsAlleles? 1/maxOffsetSlope : minOffsetSlope;
			
			outerLeftLimit = anchorViewPos - maxSlope*(anchorPos - start);
			innerLeftLimit = anchorViewPos - minSlope*(anchorPos - start);
			outerRightLimit = anchorViewPos - maxSlope*(anchorPos - end);
			innerRightLimit = anchorViewPos - minSlope*(anchorPos - end);
		
			/// We ensure that the edges of the marker don't go too far out of their position without offset
			/// This limits the risk of overlap between bin labels from different markers
			float maxDistance = (end - start)/20.0f;  		/// we allow a distance that is 5% the marker width
			if(maxDistance < 2.0f) {						/// and no less than 2.0 bp, to allow a sufficient offset for "narrow" markers
				maxDistance = 2.0f;
			}
			
			if(outerLeftLimit < start - maxDistance) {
				outerLeftLimit = start - maxDistance;
			}
			if(outerRightLimit > end + maxDistance) {
				outerRightLimit = end + maxDistance;
			}
		}
		
		if(anchorPos <= end -1 && anchorPos >= start +1.0) {		/// if the anchor point is between edges, moving an edge affects the other edge
																/// this may modify the allowed limits
			CGFloat anchorPositionRatio = (anchorPos - start) / (end - anchorPos);
			CGFloat estimatedOuterLeftLimit = anchorViewPos - (outerRightLimit - anchorViewPos) * anchorPositionRatio;
			CGFloat estimatedInnerLeftLimit = anchorViewPos - (innerRightLimit - anchorViewPos) * anchorPositionRatio;
			CGFloat estimatedOuterRightLimit = anchorViewPos + (anchorViewPos - outerLeftLimit) / anchorPositionRatio;
			CGFloat estimatedInnerRightLimit = anchorViewPos + (anchorViewPos - innerLeftLimit) / anchorPositionRatio;
			outerLeftLimit = MAX(outerLeftLimit, estimatedOuterLeftLimit);
			innerLeftLimit = MIN(estimatedInnerLeftLimit, innerLeftLimit);
			outerRightLimit = MIN(estimatedOuterRightLimit, outerRightLimit);
			innerRightLimit = MAX(estimatedInnerRightLimit, innerRightLimit);
		} else {
			/// Else the limits of the edge that is not dragged are set to the corresponding marker end.
			if(edge == leftEdge) {
				innerRightLimit = end;
				outerRightLimit = end;
			} else {
				innerLeftLimit = start;
				outerLeftLimit = start;
			}
		}
		if(edge == leftEdge) {
			leftLimit = outerLeftLimit;
			rightLimit = innerLeftLimit;
		} else {
			leftLimit = innerRightLimit;
			rightLimit = outerRightLimit;
		}
	} else {
		/// The user is about to move (not resize) the label.
		if(self.editState == editStateBinSet) {
			BaseRange binSetRange = self.binSetRange;
			float leftMargin = binSetRange.start - marker.start;
			float rightMargin = marker.end - (binSetRange.start + binSetRange.len);
			outerLeftLimit = start - leftMargin;
			innerLeftLimit = start + rightMargin;
			outerRightLimit = end + rightMargin;
			innerRightLimit = end - leftMargin;
		} else {
			CGFloat maxDistance = MAX((end - start)/20, 2.0f);
			outerLeftLimit = start - maxDistance;
			outerRightLimit = end + maxDistance;
		}
		leftLimit = outerLeftLimit;
		rightLimit = outerRightLimit;
	}
	
}


- (void)drag {
	TraceView *view = self.view;
	NSPoint mouseLocation = view.mouseLocation;
	
	if(!self.dragged) {
		/// We do not start the drag if the user has not dragged the mouse horizontally for at least 2 points.
		/// This is to avoid a drag by a single click.
		NSPoint clickedPoint = view.clickedPoint;
		CGFloat dist = fabs(mouseLocation.x - clickedPoint.x);
		if(dist < 2.0) {
			return;
		}
		self.dragged = YES;
	}
	
	/// This implementation computes the label's offset even if the user is moving the bin set and not modifying a marker offset,
	/// but we use this offset differently depending on the edit state
	CGFloat mousePos = [view sizeForX:mouseLocation.x];
	MarkerOffset offset = self.offset;
	
	float slope = offset.slope;
	float intercept = offset.intercept;
	Region *marker = self.region;
	float markerStart = marker.start;
	float markerEnd = marker.end;
	
	if(self.clickedEdge == leftEdge || self.clickedEdge == rightEdge) {
		mousePos = MIN(rightLimit, MAX(mousePos, leftLimit));
		/// we compute the slope corresponding to the mouse position. It is computed such that the offset of the anchor does not change
		float draggedEdgePos = self.clickedEdge == leftEdge? markerStart : markerEnd;
		CGFloat anchorViewPos = anchorPos * slope + intercept;
		slope = (mousePos - anchorViewPos) / (draggedEdgePos - anchorPos);
		intercept = anchorViewPos - slope * anchorPos;
		
	} else {
		/// the user is moving the label. To reflect the change, only the intercept needs to be changed
		float minIntercept = leftLimit - markerStart * slope;
		float maxIntercept = rightLimit - markerEnd * slope;
		intercept = mousePos - slope * anchorPos;
		intercept = MIN(maxIntercept, MAX(minIntercept, intercept));
	}
	
	anchorPosInView = anchorPos * slope + intercept;
	offset = MakeMarkerOffset(intercept, slope);
	if(self.editState == editStateOffset) {
		self.offset = offset;
	} else {
		[self moveByOffset:offset];
	}
	[view labelIsDragged:self];
}


- (void)setDragged:(BOOL)dragged {
	if(dragged != self.dragged) {
		_dragged = dragged;
		if(!dragged) {
			/// We hide inner and outer layers when dragging ends. It's easier to do it now
			/// than deferring it to `updateAppearance`, as `setDragged` is not called several times per cycle.
			/// This avoids cluttering the `updateAppearance` method, which is called more often.
			self.outerLayer.hidden = YES;
			self.innerLayer.hidden = YES;
			if(self.editState == editStateBinSet) {
				/// we move the bin set at the end of a drag
				if([self moveBinSet]) {
					/// The position of the anchor needs to be updated after the drag.
					[self updateAnchorPos:anchorPosInView];
				}
				/// And we restore the label's original position.
				[self moveByOffset:MarkerOffsetNone];
			} else {
				/// we update the offset of the target genotype(s) at the end of a drag
				MarkerOffset offset = self.offset;
				if(offsetAffectsAlleles) {
					offset.intercept = -offset.intercept/offset.slope;
					offset.slope = 1/offset.slope;
				}
				if([self _updateOffset: offset]) {
					[self updateAnchorPos:anchorPos];
				}
			}
			[self updateTrackingArea];
			[self performSelector:@selector(_updateHoveredState) withObject:nil afterDelay:0.05];
		} else {
			/// when dragged or resized, we show layers indicating the limits
			self.innerLayer.hidden = self.clickedEdge == betweenEdges;
			self.outerLayer.hidden = NO;
		}
	}
}


-(void) updateAnchorPos:(CGFloat)pos {
	/// We try to restore the anchor position for when the user undoes a drag.
	CGFloat previousAnchorPos = anchorPos;
	[self.view.undoManager registerUndoWithTarget:self handler:^(TraceViewMarkerLabel *target) {
		[target updateAnchorPos:previousAnchorPos];
	}];
	anchorPos = pos;

	MarkerOffset offset = self.offset;
	anchorPosInView = anchorPos * offset.slope + offset.intercept;
}


/// Moves the marker's bins by transferring the position of bin labels to their bins.
-(BOOL)moveBinSet {
	/// we first check that all bin labels are within the marker's range and that they don't overlap.
	float start = self.region.start;
	float end = self.region.end;
	NSArray *binLabels = self.binLabels;
	NSInteger binLabelCount = binLabels.count;
	for (int i = 0; i < binLabelCount; i++) {
		BinLabel *binLabel = binLabels[i];
		float startSize = binLabel.start;
		float endSize = binLabel.end;
		if(startSize < start || endSize > end) {
			/// We don't notify the user with an error because it would not be their fault. Hopefully, this should never happen.
			NSLog(@"bin '%@' edge position is out or marker '%@' range! Not applying move.", binLabel.region.name, self.region.name);
			return NO;
		}
		if(i < binLabelCount -1) {
			BinLabel *nextBinLabel = binLabels[i+1];
			if(nextBinLabel.start <= binLabel.end) {
				NSLog(@"bin '%@' overlaps bin %@! Not applying move.", binLabel.region.name, nextBinLabel.region.name);
				return NO;
			}
		}
	}
	
	/// We check that all the marker's bin are represented by our labels.
	/// If not, we cannot guaranty that all bins will have valid coordinates after the move.
	NSArray *representedBins = [binLabels valueForKeyPath:@"@unionOfObjects.region"];
	Mmarker *marker = self.region;
	NSArray *ghostBins = [marker.bins.allObjects arrayByRemovingObjectsIdenticalInArray:representedBins];
	if(ghostBins.count > 0) {
		NSLog(@"Marker '%@' has %ld bin(s) not represented by labels! Not applying move.", marker.name, ghostBins.count);
		return NO;
	}
	
	BOOL binUpdated = NO;
	for(BinLabel *binLabel in binLabels) {
		Bin *bin = binLabel.region;
		float start = bin.start;
		float startSize = binLabel.start;
		float end = bin.end;
		float endSize = binLabel.end;
		if(start != startSize || end != endSize) {
			bin.start = startSize;
			bin.end = endSize;
			binUpdated = YES;
		}
	}
	if(binUpdated) {
		[self.view.undoManager setActionName:@"Move Bins"];
	}
	return binUpdated;
}

#pragma mark - geometry


- (void)reposition {
	if(_hidden) {
		return;
	}
	
	TraceView *view = self.view;
	CGFloat hScale = view.hScale;
	if(hScale <= 0) {
		return;
	}
	
	float startSize = self.startSize;
	float endSize = self.endSize;
	CGFloat startX = [view xForSize:startSize];     /// to get our frame, we convert our position in base pairs to points (x coordinates)
	
	NSRect viewBounds = view.bounds;
	CGFloat viewBoundsOrigin = viewBounds.origin.y;
	regionRect = NSMakeRect(startX, viewBoundsOrigin, (endSize - startSize) * hScale, NSMaxY(viewBounds));
	self.frame = regionRect;

	/// the layer is a bit taller than its host view to  hide the bottom and top edges.
	NSRect layerFrame = CGRectInset(regionRect, 0.0, -2.0);
	layer.bounds = layerFrame;
	layer.position = layerFrame.origin;
	
	if(_anchorLayer && !_anchorLayer.hidden) {
		if(anchorPosInView < startSize+1 || anchorPosInView > endSize-1) {
			_anchorLayer.hidden = YES;
		}
		CGRect bounds = CGRectMake(0.0, 0.0, 1.0, layer.bounds.size.height);
		_anchorLayer.bounds = bounds;
		_anchorLayer.position = CGPointMake([view xForSize: anchorPosInView], 0.0);
		anchorSymbolLayer.position = CGPointMake(NSMidX(bounds), NSMidY(bounds));
	}
	if(_outerLayer && !_outerLayer.hidden) {
		startX =  [view xForSize:outerLeftLimit];
		CGFloat endX = [view xForSize:outerRightLimit];
		_outerLayer.frame = NSMakeRect(startX, viewBoundsOrigin, endX-startX, NSMaxY(viewBounds));
		if(_innerLayer && !_innerLayer.hidden) {
			startX =  [view xForSize:innerLeftLimit];
			endX = [view xForSize:innerRightLimit];
			_innerLayer.frame = NSMakeRect(startX, viewBoundsOrigin - 3.0, endX-startX, NSMaxY(viewBounds)+6);
		}
	}
	
	[BinLabel arrangeLabels:self.binLabels withRepositioning:YES];
}



-(void)setFrame:(NSRect)frame {
	_frame = frame;
}


- (void)updateTrackingArea {
	[super updateTrackingArea];
	if(self.editState == editStateBins) {
		/// In this state the bin labels are enabled and have tracking areas to update.
		for(BinLabel *binLabel in self.binLabels) {
			[binLabel updateTrackingArea];
		}
	}
}

#pragma mark - bins

/// Returns the range occupied by our marker's bins
-(BaseRange) binSetRange {
	float minStart = self.end;
	float maxEnd = self.start;
	
	for(Bin *bin in [self.region bins]) {
		minStart = MIN(minStart, bin.start);
		maxEnd = MAX(maxEnd, bin.end);
	}
	return MakeBaseRange(minStart, maxEnd - minStart);
}

/// Returns the maximum ratio of final width / current width that is permitted
/// while still avoiding overlaps between bins when the label is resized.
- (float)maxShrinkRatio {
	NSArray *sortedBins = [self.region sortedBins];
	NSInteger sortedBinsCount = sortedBins.count;
	float maxShrinkRatio = 0.0f;
	for (int i = 0; i < sortedBinsCount -1; i++) {
		Bin *bin1 = sortedBins[i];
		Bin *bin2 = sortedBins[i+1];
		float midBinDist =(bin2.end + bin2.start)/2 - (bin1.end + bin1.start)/2;
		float edgeDist = bin2.start - bin1.end;
		float shrinkRatio = (midBinDist - edgeDist + 0.05f) / midBinDist;
		maxShrinkRatio = MAX(shrinkRatio, maxShrinkRatio);
	}
	return maxShrinkRatio;
}


- (nullable __kindof RegionLabel*)labelWithNewBinByDraggingWithError:( NSError * _Nullable *)error {
	for(BinLabel *binLabel in self.binLabels) {
		if (binLabel.clicked) {
			/// The user must click outside a bin.
			return nil;
		}
	}
	TraceView *view = self.view;
	/// the rest is similar to the addition of new marker (see equivalent method in MarkerView.m)
	Mmarker *marker = (Mmarker*)self.region;
	CGFloat position = [view sizeForX:view.mouseLocation.x];         			/// we convert the mouse position in base pairs
	CGFloat clickedPosition =  [view sizeForX:view.clickedPoint.x];      		/// we obtain the original clicked position in base pairs
	
	/// we check if we have room for the new bin
	CGFloat safePosition = position < clickedPosition? clickedPosition - 0.13 : clickedPosition + 0.13;
	for(Bin *bin in marker.bins) {
		if(safePosition >= bin.start && safePosition <= bin.end) {
			return nil;
		}
	}
	
	BinLabel *binLabel = [RegionLabel regionLabelWithNewRegionByDraggingInView:self.view error:error];
	if(binLabel) {
		/// We add the label to the binLabel array, because this array won't update automatically since the bin
		/// is added in another context.
		binLabel.parentLabel = self;
		if(!_binLabels) {
			self.binLabels = @[binLabel];
		} else {
			NSArray *binLabels = [_binLabels arrayByAddingObject:binLabel];
			self.binLabels = [binLabels sortedArrayUsingComparator:^NSComparisonResult(BinLabel *label1, BinLabel *label2) {
				if(label1.start < label2.start) {
					return NSOrderedAscending;
				}
				return NSOrderedDescending;
			}];
		}
	}
	return binLabel;
}


-(void)updateBinLabels {
	Mmarker *marker = self.region;
	TraceView *view = self.view;
	
	NSArray *newBinLabels = [view regionLabelsForRegions:marker.bins.allObjects reuseLabels:self.binLabels];
	BOOL enable = self.editState == editStateBins;
	for(BinLabel *binLabel in newBinLabels) {
		binLabel.parentLabel = self;
		binLabel.enabled = enable;
	}
	
	/// We sort bin labels by ascending start to facilitate the management of overlap in bin names.
	self.binLabels = [newBinLabels sortedArrayUsingComparator:^NSComparisonResult(BinLabel *label1, BinLabel *label2) {
		if(label1.start < label2.start) {
			return NSOrderedAscending;
		}
		return NSOrderedDescending;
	}];
	
	self.allowsAnimations = NO;
	[BinLabel arrangeLabels:self.binLabels withRepositioning:YES];
	self.allowsAnimations = YES;
	
	needsUpdateBinLabels = NO;
}


-(void)setBinLabels:(NSArray<BinLabel *> *)binLabels {
	for(BinLabel *label in _binLabels) {
		if([binLabels indexOfObjectIdenticalTo:label] == NSNotFound) {
			[label removeFromView];
		}
	}
	_binLabels = binLabels;
	if(_highlighted && binLabels.count == 0) {
		self.editState = editStateNil;
	}
}


- (MarkerOffset) binOffset {
	return offsetAffectsAlleles? MarkerOffsetNone : _offset;
}


- (void)setOffset:(MarkerOffset)offset {
	MarkerOffset currentOffset = self.offset;
	if(currentOffset.intercept != offset.intercept || currentOffset.slope != offset.slope) {
		super.offset = offset;
		[self.view labelNeedsRepositioning:self];
	}
}


/// Moves and resized the label, and moves its bin labels, to reflect a marker offset.
///
/// The `offset` of the label is not modified and the bin widths are preserved.
/// - Parameter offset: an offset.
- (void)moveByOffset:(MarkerOffset)offset {
	Region *region = self.region;
	_start = region.start*offset.slope + offset.intercept;
	_end = region.end*offset.slope + offset.intercept;
	for(BinLabel *binLabel in self.binLabels) {
		[binLabel _shiftByOffset:offset];
	}
	[self.view labelNeedsRepositioning:self];
}


- (void)doubleClickAction:(id)sender {
	if(self.editState == editStateBins) {
		Mmarker *marker = self.region;
		TraceView *view = self.view;
		if(marker && view) {
			float size = [view sizeForX:view.mouseUpPoint.x];
			float slope = self.offset.slope;
			float intercept = self.offset.intercept;
			size = (size-intercept)/slope;    /// the position of the mouse in base pairs (in marker coordinates)

			Bin *newBin = [marker insertBinAtSize:size desiredWidth:1.0f];
			if(newBin) {
				[view.undoManager setActionName:@"Add Bin"];
				[self updateBinLabels];
				for(BinLabel *binLabel in self.binLabels) {
					if(binLabel.region == newBin) {
						binLabel.highlighted = YES;
						[binLabel spawnRegionPopover:self];
						return;
					}
				}
			}
		}
	}
}





@end
