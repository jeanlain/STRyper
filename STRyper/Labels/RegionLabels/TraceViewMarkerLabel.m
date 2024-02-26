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
#import "MarkerView.h"
#import "RulerView.h"
#import "Bin.h"
#import "BinLabel.h"
#import "Mmarker.h"




@implementation TraceViewMarkerLabel {
	
	/// When the user drags the label or its edge, we define limits for both edges
	/// "outer" limits represent the maximum width the label can take. This ensure bins remain in the marker's range
	/// inner limits represent the minimum width
	/// The width is constrained as we do not allow shrinking the binset to an arbitrary level (or to set an offset that is too extreme)
	float outerLeftLimit;
	float outerRightLimit;
	float innerLeftLimit;
	float innerRightLimit;
	
	/// These limits are visually represented by rectangular layers
	CALayer *outerLayer;
	CALayer *innerLayer;
	
	/// This is the position (in base pairs) that does not move when the label is resized
	/// This this helps adjusting the binset width so peaks fit in bins
	float anchorPos;
	
	CALayer *anchorLayer;			/// This represent the anchorPos as a vertical line
	CALayer *anchorSymbolLayer;		/// Additional symbol that convey the notion that this line won't move during resizing
	
}

# pragma mark - attributes and appearance

static NSImage *anchorImage;


+ (void)initialize {
	if (self == [TraceViewMarkerLabel class]) {
		anchorImage = [NSImage imageNamed:@"anchor"];
	}
}


- (BOOL)isMarkerLabel {
	return YES;
}


static void * const markerBinsChangedContext = (void*)&markerBinsChangedContext;

- (instancetype)init {
	self = [super init];
	if (self) {
		_offset = MarkerOffsetNone;
		
		layer = CALayer.new;
		layer.delegate = self;
		layer.opaque = YES;
		layer.anchorPoint = CGPointMake(0, 0);
		layer.actions = @{NSStringFromSelector(@selector(sublayers)): NSNull.null};
		
		/// Our layer represents the range of our region and is a light pink rectangle with black borders
		layer.zPosition = -1;  				/// this makes sure we show behind bin labels
		
		/// This type is disabled by default
		_enabled = NO;
		
		[self addObserver:self forKeyPath:@"region.bins" options:NSKeyValueObservingOptionNew context:markerBinsChangedContext];
	}
	return self;
}


- (void)setView:(TraceView *)view {
	super.view = view;
	if(layer && view) {
		layer.borderColor = view.regionLabelEdgeColor;
		[view.backgroundLayer addSublayer:layer];
	}
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context == markerBinsChangedContext) {
		[self updateBinLabels];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


-(void) removeFromView {
	[anchorLayer removeFromSuperlayer];
	[innerLayer removeFromSuperlayer];
	[outerLayer removeFromSuperlayer];
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
	TraceView *view = self.view;
	layer.backgroundColor = self.enabled? view.traceViewMarkerLabelBackgroundColor : nil;
	if(self.highlighted) {
		/// when highlighted, we make our border visible to signify that we can be resized
		layer.borderWidth = 1.0;
		if(self.dragged) {
			/// when dragged or resized, we show layers indicating the limits
			if(!outerLayer) {
				outerLayer = CALayer.new;
				outerLayer.backgroundColor = view.traceViewMarkerLabelAllowedRangeColor;
				layer.opaque = YES;
				outerLayer.zPosition = -1;
				outerLayer.actions = @{@"frame": NSNull.null, @"bounds": NSNull.null, @"position": NSNull.null};
				[self.view.backgroundLayer insertSublayer:outerLayer below:layer];
			}
			if(self.clickedEdge != betweenEdges) {
				if(!innerLayer) {					/// the inner layer is transparent, only its border is visible
					innerLayer = CALayer.new;
					innerLayer.borderWidth = 2.0;
					innerLayer.borderColor = view.regionLabelEdgeColor;
					innerLayer.zPosition = 2;		/// otherwise, this could be hidden by bins
					innerLayer.actions = @{@"frame": NSNull.null, @"bounds": NSNull.null, @"position": NSNull.null};
					[self.view.backgroundLayer addSublayer:innerLayer];
				}
				innerLayer.hidden = NO;
			} else {
				innerLayer.hidden = YES;
			}
			outerLayer.hidden = NO;
		} else {
			outerLayer.hidden = YES;
			innerLayer.hidden = YES;
		}
		if(anchorLayer && !anchorLayer.isHidden && (anchorPos < self.start + 1 || anchorPos > self.end -1)) {
			anchorLayer.hidden = YES;
			anchorPos = -1;
		}
	} else {
		layer.borderWidth = 0.0;							
		outerLayer.hidden = YES;
		innerLayer.hidden = YES;
		anchorLayer.hidden = YES;
	}
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
		if(hidden && anchorLayer) {
			/// As the anchorLayer is not a sublayer of our layer (otherwise it would show behind traces), it must be hidden separately
			anchorLayer.hidden = YES;
		}
	}
}


- (void)setHighlighted:(BOOL)highlighted {
	if(highlighted != self.highlighted) {
		EditState editState = self.editState;
		if((highlighted && (editState == editStateBinSet || editState == editStateOffset)) ||
		   /// If we get highlighted, the user must be moving the bin set or adjusting an offset
		   (!highlighted && editState != editStateBinSet && editState != editStateOffset)) {
			/// if we get de-highlighted, the user is not moving a bing set or adjusting an offset
			super.highlighted = highlighted;
		}
	}
}


- (void)setClicked:(BOOL)clicked {
	/// overridden to show our anchorLayer when appropriate
	if(clicked != self.clicked) {
		super.clicked = clicked;
		if(self.highlighted && self.clickedEdge == betweenEdges) {
			if(clickedPosition > self.start +1 && clickedPosition < self.end -1) {
				anchorPos = clickedPosition;
				if(!anchorLayer) {
					anchorLayer = CALayer.new;
					anchorLayer.delegate = self;
					anchorLayer.backgroundColor = NSColor.redColor.CGColor;
					anchorLayer.anchorPoint = CGPointMake(1, 0);
					anchorLayer.zPosition = 10.0;		/// this layer shows on top
					anchorLayer.actions = @{@"position": NSNull.null};
					anchorSymbolLayer = CALayer.new;
					anchorSymbolLayer.bounds = CGRectMake(0, 0, 15.0, 14.0);
					//	anchorSymbolLayer.actions = @{@"position": NSNull.null};
					anchorSymbolLayer.contents = (__bridge id _Nullable)([anchorImage CGImageForProposedRect:nil context:nil hints:nil]);
					[anchorLayer addSublayer:anchorSymbolLayer];
					[self.view.backgroundLayer addSublayer:anchorLayer];
					/// Because the anchor is an image that depends on the appearance, it must be set during updateForTheme (other it may not have the correct appearance).
					self.view.needsUpdateLabelAppearance = YES;
				}
				anchorLayer.hidden = NO;
				[self reposition];
			} else {
				anchorLayer.hidden = YES;
				anchorPos = -1;
			}
		}
	}
}


- (void)updateForTheme {
	TraceView *view = self.view;
	layer.borderColor = view.regionLabelEdgeColor;
	layer.backgroundColor = self.enabled? view.traceViewMarkerLabelBackgroundColor : nil;
	if(outerLayer) {
		outerLayer.backgroundColor = view.traceViewMarkerLabelAllowedRangeColor;
		innerLayer.borderColor = view.regionLabelEdgeColor;
	}
	if(anchorSymbolLayer) {
		anchorSymbolLayer.contents = (__bridge id _Nullable)([anchorImage CGImageForProposedRect:nil context:nil hints:nil]);
	}
	
	for(BinLabel *binLabel in self.binLabels) {
		[binLabel updateForTheme];
	}
}

# pragma mark -  actions / dragging

- (void)mouseDownInView {
	if(self.enabled) {
		if(!NSPointInRect(self.view.clickedPoint, self.frame)) {
			/// if the user has clicked outside our frame on the view, we end the editing of all labels showing our marker
			self.region.editState = editStateNil;
		}
		[super mouseDownInView];
	}
}



- (void)setEditState:(EditState)editState {
	if(editState == self.editState) {
		return;
	}
	
	super.editState = editState;
	
	/// if we enter the "binset" editing state, we temporarily reset our offset (otherwise, moving bins would not be intuitive).
	MarkerOffset offset = self.offset;
	MarkerOffset desiredOffset = MarkerOffsetNone;
	BOOL reposition = NO;
	if(editState == editStateBinSet) {
		if (offset.intercept != 0 || offset.slope != 1.0) {
			reposition = YES;
		}
	} else {
		/// if we enter in another state, we reestablish our offset if needed
		Genotype *genotype = [self.view.trace.chromatogram genotypeForMarker:self.region];
		if(genotype) {
			MarkerOffset genotypeOffset = genotype.offset;
			if(genotypeOffset.intercept != offset.intercept || genotypeOffset.slope != offset.slope) {
				desiredOffset = genotypeOffset;
				reposition = YES;
			}
		}
	}
	if(reposition) {
		self.offset = desiredOffset;
		[self reposition];
		self.view.rulerView.needsUpdateOffsets = YES;
	}
	
	BOOL binEnabledState = NO;
	if(editState == editStateNil) {
		self.enabled = NO;
	} else if(editState == editStateBins) {
		self.enabled = YES;
		self.highlighted = NO;		/// when the user edits bins individually, the marker label behind bins (us) is not highlighted
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
	if((edge == leftEdge || edge == rightEdge)) {
		/// when the anchor is close to an edge, we place it at the edge that is  not dragged
		if(anchorPos < start + 1 || anchorPos > end -1)  {
			anchorPos = edge == leftEdge? end : start;
		}
		
		float slope = self.offset.slope;
		float intercept = self.offset.intercept;

		/// we determine allowed limits for the edge so that the slope remains between 0.9 and 1.1
		float anchorViewPos = anchorPos*slope + intercept;
		outerLeftLimit = anchorViewPos - 1.1*(anchorPos - start);
		innerLeftLimit = anchorViewPos - 0.9*(anchorPos - start);
		outerRightLimit = anchorViewPos - 1.1*(anchorPos - end);
		innerRightLimit = anchorViewPos - 0.9*(anchorPos - end);
		
		if(self.editState == editStateBinSet) {			/// when the user is about to move the bin set
														/// the limits must ensure that the bins remain within the marker range
			BaseRange binSetRange = self.binSetRange;
			float binSetStart = binSetRange.start;
			float binSetEnd = binSetStart + binSetRange.len;
			float markerStart = self.region.start + 0.1;	/// we leave a 0.1 bp margin to make sure the bins won't go out of range
			float markerEnd = self.region.end - 0.1;
			float leftLimitForBins =0;
			float rightLimitForBins = INFINITY;
			if(anchorPos > binSetStart) {
				leftLimitForBins = markerStart - (binSetStart - markerStart) * (anchorPos - start)/(anchorPos - binSetStart);
			}
			if(anchorPos < binSetEnd) {
				rightLimitForBins = markerEnd + (markerEnd - binSetEnd) * (end - anchorPos)/(binSetEnd - anchorPos);
			}
			if(leftLimitForBins > outerLeftLimit) {
				outerLeftLimit = leftLimitForBins;
			}
			if(rightLimitForBins < outerRightLimit) {
				outerRightLimit = rightLimitForBins;
			}
		} else {
			/// if the user is modifying the offset of samples, we ensure that the edges of the marker don't go too far out of their position without offset
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
			float estimatedOuterLeftLimit =  anchorViewPos - (outerRightLimit - anchorViewPos) * anchorPositionRatio;
			float estimatedInnerLeftLimit =  anchorViewPos - (innerRightLimit - anchorViewPos) * anchorPositionRatio;
			float estimatedOuterRightLimit =  anchorViewPos + (anchorViewPos - outerLeftLimit) / anchorPositionRatio;
			float estimatedInnerRightLimit =  anchorViewPos + (anchorViewPos - innerLeftLimit) / anchorPositionRatio;
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
		}
		if(edge == leftEdge) {
			leftLimit = outerLeftLimit;
			rightLimit = innerLeftLimit;
		} else {
			leftLimit = innerRightLimit;
			rightLimit = outerRightLimit;
		}
	} else {
		if(self.editState == editStateBinSet) {
			BaseRange binSetRange = self.binSetRange;
			float leftMargin = binSetRange.start - self.region.start;
			float rightMargin = self.region.end - (binSetRange.start + binSetRange.len);
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
	/// This implementation modifies the label's offset, which it transfers to its bin labels.
	/// We do this even if the user is moving the bin set and not modifying a marker offset, as the visual feedback is the same for both
	/// But we do different things at the end of the drag depending on the edit state
	self.dragged = YES;
	
	float mousePos = [self.view sizeForX:self.view.mouseLocation.x];		/// the position of the mouse in base pairs (trace coordinates)
	float slope = self.offset.slope;
	float intercept = self.offset.intercept;
	
	if(self.clickedEdge == leftEdge || self.clickedEdge == rightEdge) {
		if(mousePos < leftLimit) {
			mousePos = leftLimit;
		} else if(mousePos > rightLimit) {
			mousePos = rightLimit;
		}
		/// we compute the slope corresponding to the mouse position. It is computed such that the offset of the anchor does not change
		float draggedEdgePos = self.clickedEdge == leftEdge? self.start : self.end;
		float anchorViewPos = anchorPos * slope + intercept;
		slope = (mousePos - anchorViewPos) / (draggedEdgePos - anchorPos);
		intercept = anchorViewPos - slope * anchorPos;
		
	} else {		
		/// the user is moving the label. To reflect the change, only the intercept need to be changed
		float minIntercept = leftLimit - self.start * slope;
		float maxIntercept = rightLimit - self.end * slope;
		intercept = mousePos - slope * clickedPosition;
		if(intercept < minIntercept){
			intercept = minIntercept;
		} else if(intercept > maxIntercept) {
			intercept = maxIntercept;
		}
	}
	
	if(intercept == self.offset.intercept && slope == self.offset.slope) {
		return;
	}
		
	MarkerOffset offset = MakeMarkerOffset(intercept, slope);
	
	self.offset = offset;
	[self reposition];
	
	if(self.editState != editStateBinSet) {
		self.view.rulerView.needsUpdateOffsets = YES;
	}
	
}


- (void)setDragged:(BOOL)dragged {
	if(dragged != self.dragged) {
		_dragged = dragged;
		if(!dragged) {
			if(self.editState == editStateBinSet) {
				/// we move the bin set at the end of a drag
				/// as our offset will be reset, we need to adjust the anchor position to compensate, 
				/// otherwise the anchor layer will move to the original clicked position at the beginning of a drag.
				MarkerOffset offset = self.offset;
				anchorPos = anchorPos * offset.slope + offset.intercept;
				[self moveBinSet];
			} else {
				/// we update the offset of the target genotype(s) at the end of a drag
				[self _updateOffset:self.offset];
			}
			[self updateTrackingArea];
			[self performSelector:@selector(_updateHoveredState) withObject:nil afterDelay:0.05];
		}
		[self updateAppearance];	/// because our inner and outer layers show depending on dragged state
	}
}




/// Moves the marker's bins by transferring the position of bin labels (considering their offset) to their bins, an resets their offset.
-(void)moveBinSet {
	/// this is like "fixing" the offset of the labels to the bin set.
	/// but we first check that all bin labels are within the marker's range.
	/// We don't check other conditions (bins overlapping and such) as they should not be modified during a drag
	float start = self.region.start;
	float end = self.region.end;
	for(BinLabel *binLabel in self.binLabels) {
		float startSize = binLabel.startSize;
		float endSize = binLabel.endSize;
		if(startSize < start || endSize > end) {
			NSLog(@"bin '%@' edge position is out or marker '%@' range! Not applying move.", binLabel.region.name, self.region.name);
			self.offset = MarkerOffsetNone;
			for(BinLabel *label in self.binLabels) {
				[label reposition];
			}
			[self reposition];
			return;
		}
	}
	BOOL binUpdated = NO;
	for(BinLabel *binLabel in self.binLabels) {
		Bin *bin = binLabel.region;
		float start = bin.start;
		float startSize = binLabel.startSize;
		float end = bin.end;
		float endSize = binLabel.endSize;
		binLabel.offset = MarkerOffsetNone;
		if(start != startSize || end != endSize) {
			bin.start = startSize;
			bin.end = endSize;
			binUpdated = YES;
		}
	}
	self.offset = MarkerOffsetNone;
	[self reposition];
	if(binUpdated) {
		[self.view.undoManager setActionName:@"Move Bin Set"];
	}
}

#pragma mark - geometry

- (void)setStart:(float)pos {
	if(self.start != pos) {
		_start = pos;
		[self reposition];
		self.view.rulerView.needsUpdateOffsets = YES;
	}
}


- (void)setEnd:(float)pos {
	if(self.end != pos) {
		_end = pos;
		[self reposition];
		if(self.offset.intercept != 0.0 || self.offset.slope != 1.0) {
			self.view.rulerView.needsUpdateOffsets = YES;
		}
	}
}


- (void)reposition {
	TraceView *view = self.view;
	float hScale = view.hScale;
	if(hScale <= 0 || self.hidden) {
		return;
	}
	
	float start = self.start;
	float end = self.end;
	MarkerOffset offset = self.offset;
	float intercept = offset.intercept;
	float slope = offset.slope;
	float startSize = start*slope + intercept;
	float endSize = end*slope + intercept;
	float startX = [view xForSize:startSize];     /// to get our frame, we convert our position in base pairs to points (x coordinates)
	
	NSRect viewBounds = view.bounds;
	float viewBoundsOrigin = viewBounds.origin.y;
	regionRect = NSMakeRect(startX, viewBoundsOrigin, (endSize - startSize) * hScale, NSMaxY(viewBounds));

	/// when highlighted, our frame (used by the tracking area) gets a bit wider so that the user can more easily click an edge to resize us
	self.frame = self.highlighted? NSInsetRect(regionRect, -2, 0) : regionRect;

	/// the layer is a bit taller than its host view to  hide the bottom and top edges.
	NSRect layerFrame = CGRectInset(regionRect, 0, -2);
	layer.bounds = layerFrame;
	layer.position = layerFrame.origin;
	
	if(anchorLayer && !anchorLayer.hidden) {
		CGRect bounds = CGRectMake(0, 0, 1, layer.bounds.size.height);
		anchorLayer.bounds = bounds;
		anchorLayer.position = CGPointMake([view xForSize: (anchorPos*slope + intercept)], 0);
		anchorSymbolLayer.position = CGPointMake(NSMidX(bounds), NSMidY(bounds));
	}
	if(outerLayer && !outerLayer.hidden) {
		startX =  [view xForSize:outerLeftLimit];
		float endX = [view xForSize:outerRightLimit];
		outerLayer.frame = NSMakeRect(startX, viewBoundsOrigin, endX-startX, NSMaxY(viewBounds));
		if(innerLayer && !innerLayer.hidden) {
			startX =  [view xForSize:innerLeftLimit]+1;
			endX = [view xForSize:innerRightLimit]-1;
			innerLayer.frame = NSMakeRect(startX, viewBoundsOrigin - 3, endX-startX, NSMaxY(viewBounds)+6);
		}
	}
	
	if(!view.isMoving && !self.dragged) {
		[self updateTrackingArea];  
	}
	
	BOOL animate = self.animated && !self.dragged;
	NSArray *binLabels = self.binLabels;
	float currentMaxX = 0; /// To avoid overlap in bin names.

	for(BinLabel *binLabel in binLabels) {
		if(!binLabel.hidden) {
			binLabel.animated = animate;
			[binLabel reposition];
			NSRect nameRect = binLabel.binNameRect;
			float nameRectMinX = nameRect.origin.x;
			if(nameRectMinX <= currentMaxX && !binLabel.hovered) {
				binLabel.binNameHidden = YES;
			} else {
				binLabel.binNameHidden = NO;
				float nameRectMaxX = NSMaxX(nameRect);
				if(nameRectMaxX > currentMaxX) {
					currentMaxX = nameRectMaxX;
				}
			}
			binLabel.animated = YES;
		}
	}
}



-(void)setFrame:(NSRect)frame {
	_frame = frame;
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


- (RegionLabel *)addLabelForBin:(Bin *)bin {
	BinLabel *binLabel = [RegionLabel regionLabelWithRegion:bin view:self.view];
	binLabel.offset = self.offset;
	[layer addSublayer:binLabel._layer];
	if(!_binLabels) {
		self.binLabels = @[binLabel];
	} else {
		self.binLabels = [_binLabels arrayByAddingObject:binLabel];
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
		binLabel.hidden = hide;
		binLabel.enabled = enable;
		if(!binLabel._layer.superlayer) {
			[layer addSublayer:binLabel._layer];
		}
	}
	
	/// We sort bin labels by ascending start to facilitate the management of overlap in bin names.
	self.binLabels = [newBinLabels sortedArrayUsingComparator:^NSComparisonResult(BinLabel * _Nonnull label1, BinLabel * _Nonnull label2) {
		if(label1.start < label2.start) {
			return NSOrderedAscending;
		}
		return NSOrderedDescending;
	}];
}


-(void)setBinLabels:(NSArray<BinLabel *> *)binLabels {
	for(BinLabel *label in _binLabels) {
		if([binLabels indexOfObjectIdenticalTo:label] == NSNotFound) {
			[label removeFromView];
		}
	}
	_binLabels = binLabels;
}


- (void)setOffset:(MarkerOffset)offset {
	super.offset = offset;
	if(_binLabels) {
		for(BinLabel *binLabel in self.binLabels) {
			binLabel.offset = offset;
		}
	}
}


- (void)dealloc {
	[self removeObserver:self forKeyPath:@"region.bins"];
}


@end
