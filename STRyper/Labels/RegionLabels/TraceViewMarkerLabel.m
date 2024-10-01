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
#import "NSArray+NSArrayAdditions.h"

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
	float outerLeftLimit;
	float outerRightLimit;
	float innerLeftLimit;
	float innerRightLimit;
	
	/// The position (in base pairs) that does not move when the label is resized and its represented by an vertical line (the anchor) when the label is dragged.
	float anchorPos; /// It is computed in the coordinates of the marker represented by the label, given its offset.
	float anchorPosInView;	/// The same, in view coordinates (still in base pairs).

	
	CALayer *anchorSymbolLayer;		/// A symbol that conveys the notion that the anchor won't move during resizing.
	Genotype *observedGenotype; 	/// The genotype we observe to react to a change of its offset.
	BOOL needsUpdateBinLabels;
	BOOL disableBinLabelAnimation;
}

# pragma mark - attributes and appearance

static NSImage *anchorImage;


+ (void)initialize {
	if (self == TraceViewMarkerLabel.class) {
		anchorImage = [NSImage imageNamed:@"anchor"];
	}
}


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
		layer.anchorPoint = CGPointMake(0, 0);
		layer.actions = @{NSStringFromSelector(@selector(sublayers)): NSNull.null};
		
		/// Our layer represents the range of our region and is a light pink rectangle with black borders
		layer.zPosition = -1;  				/// this makes sure we show behind bin labels
		
		/// This type is disabled by default
		_enabled = NO;
	}
	return self;
}


- (void)setView:(TraceView *)view {
	if(self.view) {
		[self.view removeObserver:self forKeyPath:@"trace"];
	}
	super.view = view;
	if(layer && view) {
		if(view) {
			/// We get notified if the view has loaded a new trace, as the offset of our marker depends on the sample shown.
			[view addObserver:self forKeyPath:@"trace"
					  options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
					  context:viewTraceChangedContext];
		}
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
		[self.view labelNeedsRepositioning:self];
	} else if(context == viewTraceChangedContext) {
		[self observeGenotype];
	} else if(context == genotypeOffsetChangedContext) {
		if(self.editState != editStateBinSet) {
			self.offset = observedGenotype.offset;
		}
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


- (void)observeGenotype {
	Chromatogram *sample = self.view.trace.chromatogram;
	Genotype *genotype = [sample genotypeForMarker:self.region]; /// nil if there is no sample shown
	if(genotype != observedGenotype) {
		if(self.editState == editStateOffset) {
			/// if the genotype that the view showed has changed and its offset was being edited
			/// we exit the editing.
			self.editState = editStateNil;
		}
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
	/// The label has no background color when no enabled.
	layer.backgroundColor = self.enabled? self.view.traceViewMarkerLabelBackgroundColor : nil;
	if(!self.highlighted) {
		_anchorLayer.hidden = YES;
	}
	[super updateAppearance];
}


- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	if(layer == _innerLayer || layer == _outerLayer || ((layer == _anchorLayer || layer == anchorSymbolLayer) && self.clicked) || [event isEqualToString:@"hidden"]) {
		return NSNull.null;
	}
	return [super actionForLayer:layer forKey:event];
}


- (void)setEnabled:(BOOL) state {
	if(self.enabled != state) {
		super.enabled = state;
		if(!state) {
			/// when disabled, we exit the edit state of our marker (which will affect all labels showing this marker)
			self.region.editState = editStateNil;
		}
		anchorPos = -1;
	}
}


- (void)setHidden:(BOOL)hidden {
	if(self.hidden != hidden) {
		super.hidden = hidden;
		if(hidden && _anchorLayer) {
			/// As the anchorLayer is not a sublayer of our layer (otherwise it would show behind traces), it must be hidden separately
			_anchorLayer.hidden = YES;
		}
	}
}


- (void)setClicked:(BOOL)clicked {
	/// overridden to show our anchorLayer when appropriate
	if(clicked != self.clicked) {
		super.clicked = clicked;
		if(self.highlighted && self.clickedEdge == betweenEdges) {
			MarkerOffset offset = self.offset;
			TraceView *view = self.view;
			float clickedPosition = [view sizeForX:view.clickedPoint.x];
			float clickedPositionInMarker = (clickedPosition - offset.intercept)/offset.slope;
			if(clickedPositionInMarker > self.start +1 && clickedPositionInMarker < self.end -1) {
				anchorPos = clickedPositionInMarker;
				anchorPosInView = clickedPosition;
				self.anchorLayer.hidden = NO;
				/// Since the anchor layer must be repositioned with the label whenever it shows
				/// we just reposition the whole label rather than setting `needsUpdateAppearance`.
			} else {
				anchorPos = anchorPosInView = -1;
			}
			[self.view labelNeedsRepositioning:self];
		}
	}
}


- (void)updateForTheme {
	TraceView *view = self.view;
	layer.borderColor = view.regionLabelEdgeColor;
	layer.backgroundColor = self.enabled? view.traceViewMarkerLabelBackgroundColor : nil;
	_outerLayer.backgroundColor = view.traceViewMarkerLabelAllowedRangeColor;
	_innerLayer.borderColor = view.regionLabelEdgeColor;
	anchorSymbolLayer.contents = (__bridge id _Nullable)([anchorImage CGImageForProposedRect:nil context:nil hints:nil]);
	
	for(BinLabel *binLabel in self.binLabels) {
		[binLabel updateForTheme];
	}
}

# pragma mark -  actions / dragging

- (CALayer *)innerLayer {
	if(!_innerLayer) {
		TraceView *view = self.view;
		_innerLayer = CALayer.new;
		_innerLayer.borderWidth = 2.0;
		_innerLayer.borderColor = view.regionLabelEdgeColor;
		_innerLayer.zPosition = 2;		/// otherwise, this could be hidden by bins
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
		_anchorLayer.anchorPoint = CGPointMake(1, 0);
		_anchorLayer.zPosition = 10.0;		/// this layer shows on top
		_anchorLayer.delegate = self;
		anchorSymbolLayer = CALayer.new;
		anchorSymbolLayer.delegate = self;
		anchorSymbolLayer.bounds = CGRectMake(0, 0, 15.0, 14.0);
		[_anchorLayer addSublayer:anchorSymbolLayer];
		TraceView *view = self.view;
		[view.backgroundLayer addSublayer:_anchorLayer];
		
		/// Because the anchorSymbolLayer is an image that depends on the app appearance,
		/// it must be set during updateForTheme to have the correct appearance.
		view.needsUpdateLabelAppearance = YES;
	}
	return _anchorLayer;
}


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
		self.dragged = NO;
	}
}



- (void)setEditState:(EditState)editState {
	if(editState == self.editState) {
		return;
	}
	
	if(editState == editStateBinSet) {
		/// if we enter this edit state, we make as if the marker had no offset (otherwise, moving bins would not be intuitive).
		self.offset = MarkerOffsetNone;
	}
	
	if(self.editState == editStateBinSet) {
		/// if we exit the "binset" edit stage, we get back the offset of the genotype at our marker
		if(observedGenotype) {
			self.offset = observedGenotype.offset;
		}
	}
	
	super.editState = editState;
	
	BOOL binEnabledState = NO;
	if(editState == editStateNil) {
		self.enabled = NO;
	} else if(editState == editStateBins) {
		self.enabled = YES;
		self.highlighted = NO;		/// When the user edits bins individually, the marker label behind bins (us) is not highlighted
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

		float anchorViewPos = anchorPos*slope + intercept;
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
			float firstBinAllowedPos = marker.start + 0.1 + firstBinWidth * 0.5;	/// we leave a 0.1 bp margin to make sure the bins won't go out of range
			float lastBinAllowedPos = marker.end - 0.1 - lastBinWidth * 0.5;
			
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
			/// we determine allowed limits for the edge so that the slope remains between 0.9 and 1.1
			outerLeftLimit = anchorViewPos - 1.1*(anchorPos - start);
			innerLeftLimit = anchorViewPos - 0.9*(anchorPos - start);
			outerRightLimit = anchorViewPos - 1.1*(anchorPos - end);
			innerRightLimit = anchorViewPos - 0.9*(anchorPos - end);
		
			/// We ensure that the edges of the marker don't go too far out of their position without offset
			/// This limits the risk of overlap between bin labels from different markers
			float maxDistance = (end - start)/20;  		/// we allow a distance that is 5% the marker width
			if(maxDistance < 2.0) {						/// and no less than 2.0 bp, to allow a sufficient offset for "narrow" markers
				maxDistance = 2.0;
			}
			
			if(outerLeftLimit < start - maxDistance) {
				outerLeftLimit = start - maxDistance;
			}
			if(outerRightLimit > end + maxDistance) {
				outerRightLimit = end + maxDistance;
			}
		}
		
		if(anchorPos <= end -1 && anchorPos >= start +1) {		/// if the anchor point is between edges, moving an edge affects the other edge
																/// this may modify the allowed limits
			float anchorPositionRatio = (anchorPos - start) / (end - anchorPos);
			float estimatedOuterLeftLimit = anchorViewPos - (outerRightLimit - anchorViewPos) * anchorPositionRatio;
			float estimatedInnerLeftLimit = anchorViewPos - (innerRightLimit - anchorViewPos) * anchorPositionRatio;
			float estimatedOuterRightLimit = anchorViewPos + (anchorViewPos - outerLeftLimit) / anchorPositionRatio;
			float estimatedInnerRightLimit = anchorViewPos + (anchorViewPos - innerLeftLimit) / anchorPositionRatio;
			if(outerLeftLimit < estimatedOuterLeftLimit) {
				outerLeftLimit = estimatedOuterLeftLimit;
			}
			if(innerLeftLimit > estimatedInnerLeftLimit) {
				innerLeftLimit = estimatedInnerLeftLimit;
			}
			if(outerRightLimit > estimatedOuterRightLimit) {
				outerRightLimit = estimatedOuterRightLimit;
			}
			if(innerRightLimit < estimatedInnerRightLimit) {
				innerRightLimit = estimatedInnerRightLimit;
			}
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
			float maxDistance = (end - start)/20;
			if(maxDistance < 2.0) {
				maxDistance = 2.0;
			}
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
		float dist = fabs(mouseLocation.x - clickedPoint.x);
		if(dist < 2) {
			return;
		}
		self.dragged = YES;
	}
	
	/// This implementation computes the label's offset even if the user is moving the bin set and not modifying a marker offset,
	/// but we use this offset differently depending on the edit state
	float mousePos = [view sizeForX:mouseLocation.x];
	float slope = self.offset.slope;
	float intercept = self.offset.intercept;
	Region *marker = self.region;
	float markerStart = marker.start;
	float markerEnd = marker.end;
	
	if(self.clickedEdge == leftEdge || self.clickedEdge == rightEdge) {
		if(mousePos < leftLimit) {
			mousePos = leftLimit;
		} else if(mousePos > rightLimit) {
			mousePos = rightLimit;
		}
		/// we compute the slope corresponding to the mouse position. It is computed such that the offset of the anchor does not change
		float draggedEdgePos = self.clickedEdge == leftEdge? markerStart : markerEnd;
		float anchorViewPos = anchorPos * slope + intercept;
		slope = (mousePos - anchorViewPos) / (draggedEdgePos - anchorPos);
		intercept = anchorViewPos - slope * anchorPos;
		
	} else {
		/// the user is moving the label. To reflect the change, only the intercept need to be changed
		float minIntercept = leftLimit - markerStart * slope;
		float maxIntercept = rightLimit - markerEnd * slope;
		intercept = mousePos - slope * anchorPos;
		if(intercept < minIntercept){
			intercept = minIntercept;
		} else if(intercept > maxIntercept) {
			intercept = maxIntercept;
		}
	}
	
	anchorPosInView = anchorPos * slope + intercept;
	MarkerOffset offset = MakeMarkerOffset(intercept, slope);
	if(self.editState == editStateOffset) {
		self.offset = offset;
	} else {
		[self moveByOffset:offset];
	}
	[view labelIsDragged:self];
}


- (void)setDragged:(BOOL)dragged {
	if(dragged != self.dragged) {
		if(!dragged) {
			/// We hide inner and outer layers when dragging ends. It's easier to do it now
			/// than deferring it to `updateAppearance`, as `setDragged` should not be called several times per cycle.
			/// This avoids cluttering the `updateAppearance` method, which is called more often.
			_outerLayer.hidden = YES;
			_innerLayer.hidden = YES;
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
				if([self _updateOffset:self.offset]) {
					[self updateAnchorPos:anchorPos];
				}
			}
			[self updateTrackingArea];
			[self performSelector:@selector(_updateHoveredState) withObject:nil afterDelay:0.05];
		} else {
			/// when dragged or resized, we show layers indicating the limits
			if(self.clickedEdge != betweenEdges) {
				self.innerLayer.hidden = NO;
			} else {
				_innerLayer.hidden = YES;
			}
			self.outerLayer.hidden = NO;
		}
		_dragged = dragged;
	}
}


-(void) updateAnchorPos:(float)pos {
	/// We try to restore the anchor position for when the user undoes a drag.
	float previousAnchorPos = anchorPos;
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
	BOOL binUpdated = NO;
	for(BinLabel *binLabel in self.binLabels) {
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
		[self.view.undoManager setActionName:@"Move Bin Set"];
	}
	return binUpdated;
}

#pragma mark - geometry


- (void)reposition {
	TraceView *view = self.view;
	float hScale = view.hScale;
	if(hScale <= 0 || self.hidden) {
		return;
	}
	
	float startSize = self.startSize;
	float endSize = self.endSize;
	float startX = [view xForSize:startSize];     /// to get our frame, we convert our position in base pairs to points (x coordinates)
	
	NSRect viewBounds = view.bounds;
	float viewBoundsOrigin = viewBounds.origin.y;
	regionRect = NSMakeRect(startX, viewBoundsOrigin, (endSize - startSize) * hScale, NSMaxY(viewBounds));
	self.frame = regionRect;

	/// the layer is a bit taller than its host view to  hide the bottom and top edges.
	NSRect layerFrame = CGRectInset(regionRect, 0, -2);
	layer.bounds = layerFrame;
	layer.position = layerFrame.origin;
	
	if(_anchorLayer && !_anchorLayer.hidden) {
		if(anchorPosInView < startSize+1 || anchorPosInView > endSize-1) {
			_anchorLayer.hidden = YES;
		}
		CGRect bounds = CGRectMake(0, 0, 1, layer.bounds.size.height);
		_anchorLayer.bounds = bounds;
		_anchorLayer.position = CGPointMake([view xForSize: anchorPosInView], 0);
		anchorSymbolLayer.position = CGPointMake(NSMidX(bounds), NSMidY(bounds));
	}
	if(_outerLayer && !_outerLayer.hidden) {
		startX =  [view xForSize:outerLeftLimit];
		float endX = [view xForSize:outerRightLimit];
		_outerLayer.frame = NSMakeRect(startX, viewBoundsOrigin, endX-startX, NSMaxY(viewBounds));
		if(_innerLayer && !_innerLayer.hidden) {
			startX =  [view xForSize:innerLeftLimit];
			endX = [view xForSize:innerRightLimit];
			_innerLayer.frame = NSMakeRect(startX, viewBoundsOrigin - 3, endX-startX, NSMaxY(viewBounds)+6);
		}
	}
	
	if(needsUpdateBinLabels) {
		[self updateBinLabels];
	}
	
	[BinLabel arrangeLabels:self.binLabels withRepositioning:YES allowAnimations:self.allowsAnimations && !_dragged &&!disableBinLabelAnimation];
	disableBinLabelAnimation = NO;
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
		float binStart = bin.start;
		if(binStart < minStart) {
			minStart = binStart;
		}
		float binEnd = bin.end;
		if(binEnd > maxEnd) {
			maxEnd = binEnd;
		}
	}
	return MakeBaseRange(minStart, maxEnd - minStart);
}

/// Returns the maximum ratio of final width / current width that is permitted
/// while still avoiding overlaps between bins when the label is resized.
- (float)maxShrinkRatio {
	NSArray *sortedBins = [self.region sortedBins];
	NSInteger sortedBinsCount = sortedBins.count;
	float maxShrinkRatio = 0;
	for (int i = 0; i < sortedBinsCount -1; i++) {
		Bin *bin1 = sortedBins[i];
		Bin *bin2 = sortedBins[i+1];
		float midBinDist =(bin2.end + bin2.start)/2 - (bin1.end + bin1.start)/2;
		float edgeDist = bin2.start - bin1.end;
		float shrinkRatio = (midBinDist - edgeDist + 0.05) / midBinDist;
		if(shrinkRatio > maxShrinkRatio) {
			maxShrinkRatio = shrinkRatio;
		}
	}
	return maxShrinkRatio;
}


- (nullable __kindof RegionLabel*)labelWithNewBinByDraggingWithError:( NSError * _Nullable *)error {
	BinLabel *binLabel = [RegionLabel regionLabelWithNewRegionByDraggingInView:self.view error:error];
	if(binLabel) {
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
	BOOL hide = !view.showDisabledBins && !self.enabled && view.trace != nil;		/// we hide the new bin labels if needed.
	BOOL enable = self.editState == editStateBins;
	for(BinLabel *binLabel in newBinLabels) {
		binLabel.parentLabel = self;
		binLabel.hidden = hide;
		binLabel.enabled = enable;
	}
	
	/// We sort bin labels by ascending start to facilitate the management of overlap in bin names.
	self.binLabels = [newBinLabels sortedArrayUsingComparator:^NSComparisonResult(BinLabel *label1, BinLabel *label2) {
		if(label1.start < label2.start) {
			return NSOrderedAscending;
		}
		return NSOrderedDescending;
	}];
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
	[self.view labelNeedsRepositioning:self];
	disableBinLabelAnimation = YES; /// We don't want bin labels to animate after we get new labels.
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


@end
