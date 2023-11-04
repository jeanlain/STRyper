//
//  PeakLabel.m
//  STRyper
//
//  Created by Jean Peccoud on 05/01/13.
//  Copyright (c) 2013 Jean Peccoud. All rights reserved.
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


#import "PeakLabel.h"
#import "TraceView.h"
#import "FragmentLabel.h"
#import "Allele.h"
#import "Bin.h"
#import "RegionLabel.h"
#import "Mmarker.h"
#import "Genotype.h"




@interface PeakLabel ()

/// property redeclared as readwrite.
@property (weak, nonatomic, nullable) LadderFragment *fragment;

@end


@implementation PeakLabel {
	__weak Mmarker *marker; 				/// see property with the same name
	__weak RegionLabel *targetBinLabel;		/// the bin label that is the current target of a drag
	NSPoint startPoint;						/// to implement dragging behavior. Position of the dragging handle fixed point
	NSPoint handlePosition;					/// position of the dragging handle that is controlled by the mouse
	NSToolTipTag toolTipTag;				/// The tag of the tooltip showing peak information on our view
}

#pragma mark - initialization and base attributes setting

static CALayer *lineLayer;  /// The vertical line that shows that the label is hovered, at the peak tip
							/// We use a single instance for the class as no more than one label can be hovered at a time

+ (void)initialize {
	//peakArea = [NSBezierPath bezierPath];
	
	lineLayer = CALayer.new;
	lineLayer.backgroundColor = NSColor.blackColor.CGColor;
	lineLayer.opaque = YES;
	lineLayer.zPosition = -0.3; /// so that it doesn't show above fragment labels
	
	dragLineLayer = CALayer.new;
	dragLineLayer.anchorPoint = CGPointMake(0, 0);
	dragLineLayer.contentsScale = 2.0;
	dragLineLayer.shadowOpacity = 1.0;
	dragLineLayer.shadowRadius = 1.0;
	dragLineLayer.shadowOffset = CGSizeMake(0, -1);
	
}


- (instancetype)init {
	return [self initWithPeak:MakePeak(0, 0, 0, 0) view:TraceView.new];
}



- (instancetype)initWithPeak:(Peak)peak view:(nonnull TraceView *)view {
	self = [super init];
	if (self) {
		_startScan = peak.startScan;
		_scan = peak.scansToTip + peak.startScan;
		_endScan = _scan + peak.scansFromTip;
		_crossTalk = peak.crossTalk;
		_trace = view.trace;
		self.view = view;
	}
	return self;
}


- (id)representedObject {
	return self.fragment;
}


- (float) size {
	return [self.trace sizeForScan:self.scan];
}


- (LadderFragment *)fragment {
	if(_fragment && _fragment.scan == self.scan) {
		return _fragment;
	}
	for (LadderFragment *peak in self.trace.fragments) {
		if (peak.scan == self.scan) {
			_fragment = peak;
			return _fragment;
		}
	}
	_fragment = nil;
	return _fragment;
}


-(nullable Mmarker *) marker {
	if(self.trace.isLadder) {
		return nil;
	}
	Chromatogram *sample = self.trace.chromatogram;
	float size = [sample sizeForScan:self.scan];
	for (Mmarker *marker in [sample.panel markersForChannel:self.trace.channel]) {
		if(size >= marker.start && size <= marker.end)  {
			return marker;
		}
	}
	return nil;
	
}


# pragma mark - tracking area and geometry


- (void)updateTrackingArea {
	TraceView *view = self.view;
	[self reposition];			/// our view doesn't reposition us during geometry change, so we reposition here. TO CHANGE ?
	[super updateTrackingArea];
	/// This is the appropriate method to update the tooltip rect (doing it every time we reposition is unnecessary)
	
	if(view.showPeakTooltips && self.enabled) {
		toolTipTag = [view addToolTipRect:self.frame owner:self userData:nil];
	}
}


- (void)removeTrackingArea {
	[super removeTrackingArea];
	if(toolTipTag != 0) {
		[self.view removeToolTip:toolTipTag];
		toolTipTag = 0;
	}
}


- (void)reposition {
	TraceView *view = self.view;
	if(view.hScale <= 0) {
		return;
	}
	float startX = round([view xForScan:self.startScan] - 0.5);
	self.frame = NSMakeRect(startX, 0, [view xForScan:self.endScan] - startX, NSMaxY(view.bounds));
	if(self.hovered) {
		[self updateAppearance];
	}
}


-(void)setFrame:(NSRect)frame {
	_frame = frame;
}


# pragma mark - drawing and appearance


- (NSString *)description {
	/// used for the tooltip, since -stringForToolTip is deprecated
	BOOL noSizing = self.trace.chromatogram.sizingQuality.floatValue == 0;
	NSString *sizeInfo = @"unavailable";
	if(!noSizing) {
		sizeInfo = [NSString stringWithFormat:@"%.01f bp", self.size];
	}
	int16_t fluo = [self.view.trace fluoForScan:self.scan useRawData:self.view.showRawData maintainPeakHeights:self.view.maintainPeakHeights];
	NSString *string = [NSString stringWithFormat:@"Scan: %d\nSize: %@\nFluorescence: %d RFU", self.scan, sizeInfo, fluo];
	if(self.crossTalk < 0) {
		string = [string stringByAppendingString:@"\nCaution: crosstalk"];
	}
	return string;
}


- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	if(layer == lineLayer || layer == dragLineLayer) {
		return NSNull.null;
	}
	return [super actionForLayer:layer forKey:event];
}


- (void)updateAppearance {
	if(self.hovered) {
		lineLayer.delegate = self;	/// useful to determine if we show the vertical line
		lineLayer.hidden = NO;
		TraceView *view = self.view;
		float tipPos = [view xForScan:self.scan];
		
		lineLayer.frame = CGRectMake(tipPos, 0, 1, self.frame.size.height);
		CALayer *viewLayer = view.layer;
		if(lineLayer.superlayer != viewLayer) {
			[viewLayer addSublayer:lineLayer];
		}
	} else {
		if(lineLayer.delegate == self) {
			lineLayer.hidden = YES;
			lineLayer.delegate = nil;
		}
	}
	
	/// we don't have layers to represent ourself. So when our appearance needs to be updated, the view must draw us
	//[self.view setNeedsDisplayInRect: NSInsetRect(self.frame, -1, -1)];
}



/*
/// the paths that draws the peak area (filled) when the label is highlighted.
/// Since only one label can draw at a time, we use a shared instance. Maybe we should not.
static NSBezierPath *peakArea;



- (void)draw {

	
	if (self.hovered) {
		[self drawHoveredState];
	}
//	[self drawDefaultState];  /// The label draws nothing when it is not hovered, but this can be used for debugging purposes, in particular when one needs to know the scan number of a peak
}


/// Draws the label in its hovered state.
- (void)drawHoveredState {
	/// Draws a vertical line at the location of the peak tip.
	float ourXPosition = [self.view xForScan:self.scan];
	[lineColor setStroke];
	[NSBezierPath strokeLineFromPoint:NSMakePoint(ourXPosition, NSMinY(self.frame)) toPoint: NSMakePoint(ourXPosition, NSMaxY(self.frame))];
//	[self drawDefaultState];
}

/// Draws the label in its highlighted state (paints the peak area)
///
/// This is no longer used, we don't show the peak highlighted state (it was useful when a peak label showed a menu, which is no longer the case.
/// We keep the method here in case we need it in the future.
- (void)drawHighlightedState {
	/// Paints the peak area under the curve with the color corresponding to the channel
	NSColor *peakColor = self.view.colorsForChannels[self.trace.channel];
	[peakColor setFill];
	[peakColor setStroke];
	
	[peakArea moveToPoint:NSMakePoint([self.view xForScan:self.startScan], self.view.verticalOffset)];
	for (int x = self.startScan; x <= self.endScan; x++) {
		NSPoint point = [self.view pointForScan:x];
		if (point.y < 0) point.y = 0;
		[peakArea lineToPoint:point];
	}
	[peakArea lineToPoint: NSMakePoint([self.view xForScan:self.endScan], self.view.verticalOffset)];
	[peakArea closePath];
	[peakArea fill];
	[peakArea stroke];
	[peakArea removeAllPoints];

	//[self drawDefaultState];
}

/// This is for debugging purposes.
- (void)drawDefaultState {

	/// Paints a red circle around the apex, or does nothing, depending on view options
	if ([NSUserDefaults.standardUserDefaults boolForKey:OutlinePeaks]) {
		CGPoint apex = [self.view pointForScan:self.scan];
		if(self.crossTalk < 0){
			[NSColor.redColor setStroke];
		}
		else {
			[NSColor.blackColor setStroke];
		}
		[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(apex.x - 3, apex.y - 3, 6, 6)] stroke];
		NSString *size = [NSString stringWithFormat:@"%d", self.scan];
		[size drawAtPoint:NSMakePoint(apex.x, apex.y) withAttributes:@{NSFontAttributeName: [NSFont labelFontOfSize:9]}];
	}
}
*/

# pragma mark - dragging behavior

/// The layer that draw the handle from the peak label when the user drags.
/// We use a single instance for all  peak labels, since only one handle show appear at a time
static CALayer *dragLineLayer;


/// draws a handle from the peak to the mouse, to assign a peak to a bin (manual genotyping)
- (void)drag {
	self.dragged = YES;
	
	if(self.dragged) {	/// The drag may not be effective (see setDragged:).
		TraceView *view = self.view;
		NSPoint mouseLocation = view.mouseLocation;
		targetBinLabel = nil;
			
		/// We highlight the bin label that is under the mouse
		/// They won't highlight by themselves because bin labels are disabled when peak labels are enabled.
		/// We could enable them just for this situation, but this won't be more elegant nor easier.
		for(RegionLabel *markerLabel in view.markerLabels) {
			if(markerLabel.region == marker) {
				for(RegionLabel *binLabel in markerLabel.binLabels) {
					if (NSPointInRect(mouseLocation, binLabel.frame)) {
						targetBinLabel = binLabel;
						binLabel.hovered = YES;
						break;
					} else {
						binLabel.hovered = NO;
					}
				}
				break;
			}
		}
		
		handlePosition.y = mouseLocation.y;
		if(targetBinLabel) {
			/// if the mouse is within a bin, we set the x position of the handle to the middle of the bin (some sort of magnetism)
			float midBinX = NSMidX(targetBinLabel.frame);
			if(handlePosition.x != midBinX) {
				/// If the handle was not previously in the bin, we signify magnetism with haptic feedback
				[NSHapticFeedbackManager.defaultPerformer performFeedbackPattern:NSHapticFeedbackPatternAlignment
																 performanceTime:NSHapticFeedbackPerformanceTimeDefault];
			}
			handlePosition.x = midBinX;
		} else {
			handlePosition.x = mouseLocation.x;
		}
		
		/// we prepare the layer that draws the connection line.
		/// This layer goes from the start point of the drag to the end point, and takes the whole view height
		/// We could make it larger, but performance is better when the layer is not larger than needed
		float distX = ceil(startPoint.x - handlePosition.x);
		float x = distX < 0? startPoint.x : handlePosition.x;
		CGRect frame = CGRectMake(x - 5, 0, fabsf(distX) + 10, view.frame.size.height);
		dragLineLayer.frame = frame;
		dragLineLayer.bounds = frame; /// so the layer coordinates match those of its super layer (hence the trace view).
		[dragLineLayer setNeedsDisplay];

	}
}


- (void)setHovered:(BOOL)hovered {
	if(self.dragged && !hovered) {
		return;				/// a peak label that is dragged keeps its hovered state
	}
	[super setHovered:hovered];
}


- (void)setDragged:(BOOL)dragged {
	if(dragged != self.dragged) {
		TraceView *view = self.view;
		NSPoint mouseLocation = view.mouseLocation;
		if(dragged) {
			if(!self.dragged) {
				if(view.binLabels.count == 0 || !view.showDisabledBins) {
					/// The user would do nothing with the handle if there is no bin.
					return;
				}
				/// We do not start the drag if the user has not dragged the mouse for at least 5 points.
				/// This avoids assigning the peak to an allele for what could be a simple click.
				NSPoint clickedPoint = view.clickedPoint;
				float dist = pow(pow(mouseLocation.x - clickedPoint.x, 2.0) + pow(mouseLocation.y - clickedPoint.y, 2.0), 0.5);
				if(dist < 5) {
					return;
				}
			}
			marker = self.marker;
			if(marker.bins.count == 0) {
				/// we don't do the drag behavior the peak is not within a marker or the marker has no bin
				return;
			}
			/// we set the start point of the drag line, which we place horizontally at the peak tip (and vertically where the mouse was clicked)
			startPoint = self.view.clickedPoint;
			startPoint.y -=2;	/// this makes the handle closer to the cursor arrow tip
			startPoint.x = [self.view xForScan:self.scan];
			dragLineLayer.delegate = self;
			[self.view.layer addSublayer:dragLineLayer];
		} else {
			/// here the mouse has been released after we were dragged
			targetBinLabel.hovered = NO;
			if(!NSPointInRect(mouseLocation, self.frame)) {
				self.hovered = NO;
			}
			[dragLineLayer setNeedsDisplay]; /// this clears the layer
			[self attachAlleleWithBin:targetBinLabel.region];
		}
		_dragged = dragged;
	}
}


/// Names an allele after a bin and give it our scan.
/// Bin can be nil, in which case the allele gets the "out of bin" name
/// This does not create a new allele, as the ploidy is fixed. We rename an move (attach) an existing allele if necessary.
-(void) attachAlleleWithBin:(Bin *)bin {
															
	NSString *name = bin.name;
	if(!name) {
		name = [NSUserDefaults.standardUserDefaults stringForKey:DubiousAlleleName];
	}
	if(!name) {
		name = @"?";
	}
	
	int scan = self.scan;
	/// we find a suitable allele, which will be the one closest to our position (which would be the allele we already have, if any)
	Mmarker *marker = bin.marker? bin.marker : self.marker;
	Genotype *genotype = [self.trace.chromatogram genotypeForMarker:marker];
	if(genotype) {
		Allele *closestAllele = nil;
		/// we also the distance between the allele scan and our scan (used below).
		int minDist = INT_MAX;
		for(Allele *allele in genotype.alleles) {
			int32_t alleleScan = allele.scan;
			if(alleleScan <= 0 || alleleScan == scan) {
				/// if there is an allele available (not used) we give it our scan. We may do this for all alleles available, creating a homozygote.
				/// we do the same for alleles that are at our scan (and which we represent)
				allele.scan = scan;  	/// we give our scan position to the allele
				allele.name = name;
				self.fragment = allele;
			} else {
				if(abs(alleleScan - scan) < minDist) {
					minDist = abs(alleleScan - scan);
					closestAllele = allele;
				}
			}
		}
		if(!self.fragment && closestAllele) {
			/// If no allele is available or at our scan, we choose the one that is closest to our scan.
			closestAllele.name = name;
			closestAllele.scan = scan;
			self.fragment = closestAllele;
		}
		genotype.status = genotypeStatusManual;
		[self.view.undoManager setActionName:@"Edit Genotype"];
	}
}


/// draws the handle during drag
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
	if(layer == dragLineLayer) {
		if(!self.dragged) {
			/// This removes the handle after being dragged
			return;
		}
		NSGraphicsContext *nsGraphicsContext;
		nsGraphicsContext = [NSGraphicsContext graphicsContextWithCGContext:ctx
																	flipped:NO];
		[NSGraphicsContext saveGraphicsState];
		NSGraphicsContext.currentContext = nsGraphicsContext;
		
		[NSColor.grayColor set];
		NSPoint start = startPoint;
		NSRect origin = NSMakeRect(start.x-3,start.y -3, 6, 6);
		
		NSPoint point2 = handlePosition;
		float maxY = NSMaxY(self.view.frame) -3;
		if(point2.y > maxY) {
			point2.y = maxY;
		} else if(point2.y < 2) {
			point2.y = 2;
		}
		point2.y += 2;
				
		NSRect current = NSMakeRect(point2.x-3, point2.y-3, 6, 6);
		
		NSBezierPath *thePath = [NSBezierPath bezierPathWithOvalInRect:origin];
		[thePath fill];
		
		thePath = [NSBezierPath bezierPathWithOvalInRect:current];
		[thePath fill];
		
		[NSBezierPath strokeLineFromPoint:start toPoint:point2];
		
		[NSGraphicsContext restoreGraphicsState];
	}
}


# pragma mark - other

/// Removes the allele(s) at our scan.
- (void)removeAllele:(id)sender {
	Allele *ourAllele = (Allele*)self.fragment;
	for(Allele *allele in ourAllele.genotype.alleles) {
		if(allele.scan == self.scan) {
			/// We remove any allele at our scan (ours included). We assume that the user wants to remove all alleles at the peak
			allele.scan = 0;
		} else {
			/// if there is another allele, we use its values to make a homozygote
			ourAllele.scan = allele.scan;
			ourAllele.name = allele.name;
		}
	}
	self.fragment = nil;
	if(ourAllele.genotype) {
		ourAllele.genotype.status = genotypeStatusManual;
	}
	[self.view.undoManager setActionName:@"Edit Genotype"];
}


/// Allows the user to assign/detach an allele to the peak we represent
- (void)doubleClickAction:(id)sender {
	Mmarker *marker = self.marker;
	if(self.trace.isLadder || !marker) {
		return;
	}
	if(self.fragment) {
		/// if we already have an allele at our peak, we remove it
		[self removeAllele:sender];
	} else {
		/// else we find an an allele (or alleles) to add to our peak
		Bin *ourBin;		/// we attach it to the bin at our position, if any
		float ourSize = self.size;
		for(Bin *bin in marker.bins) {
			if(bin.start <= ourSize && bin.end >= ourSize) {
				ourBin = bin;
				break;
			}
		}
		[self attachAlleleWithBin:ourBin];
	}
}





@end
