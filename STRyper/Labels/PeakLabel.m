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
	__weak Trace *trace;					/// The trace of which the label represents a peak
	__weak Mmarker *marker; 				/// see property with the same name
	__weak RegionLabel *targetBinLabel;		/// the bin label that is the current target of a drag
	NSPoint startPoint;						/// to implement dragging behavior. Position of the dragging handle fixed point
	NSPoint handlePosition;					/// position of the dragging handle that is controlled by the mouse
	NSToolTipTag toolTipTag;				/// The tag of the tooltip showing peak information on our view
}

#pragma mark - initialization and base attributes setting

+ (void)initialize {
	dragLineLayer = CALayer.new;
	dragLineLayer.anchorPoint = CGPointMake(0, 0);
	dragLineLayer.contentsScale = 2.0;
	dragLineLayer.shadowOpacity = 1.0;
	dragLineLayer.shadowRadius = 1.0;
	dragLineLayer.shadowOffset = CGSizeMake(0, -1);
}


- (instancetype)init {
	return [self initWithPeak:MakePeak(0, 0, 0, 0) view:nil];
}



- (instancetype)initWithPeak:(Peak)peak view:(TraceView *)view {
	self = [super init];
	if (self) {
		self.view = view;
		self.peak = peak;
	}
	return self;
}


- (id)representedObject {
	return self.fragment;
}


- (void)setPeak:(Peak)peak {
	_startScan = peak.startScan;
	_scan = peak.scansToTip + peak.startScan;
	_endScan = _scan + peak.scansFromTip;
	_crossTalk = peak.crossTalk;	
	trace = self.view.trace;  /// if the label is asiigned another peak  it is safer to update the trace as well.
							  /// We could do it via KVO, but it's faster this way.
							  /// It the view gets a new trace, it has to assign labels to new peaks anyway (or create new labels).
}


- (float) size {
	return [trace sizeForScan:self.scan];
}


- (LadderFragment *)fragment {
	if(!_fragment || _fragment.scan != self.scan) {
		_fragment = nil;
		for (LadderFragment *fragment in trace.fragments) {
			if (fragment.scan == self.scan) {
				_fragment = fragment;
				return _fragment;
			}
		}
	}
	return _fragment;
}


-(nullable Mmarker *) marker {
	if(trace && !trace.isLadder) {
		Chromatogram *sample = trace.chromatogram;
		float size = [sample sizeForScan:self.scan];
		for (Mmarker *marker in [sample.panel markersForChannel:trace.channel]) {
			if(size >= marker.start && size <= marker.end)  {
				return marker;
			}
		}
	}
	return nil;
}


- (nullable NSMenu *)menu {
	if(trace.isLadder) {
		if(self.fragment) {
			NSMenu *menu = NSMenu.new;
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Remove from Sizing" action:@selector(removeFragment:) keyEquivalent:@""];
			item.target = self;
			[menu addItem:item];
			return menu;
		}
	} else if(self.marker) {
		LadderFragment *fragment = self.fragment;
		NSMenu *menu = NSMenu.new;
		if(fragment) {
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Remove Peak" action:@selector(removeFragment:) keyEquivalent:@""];
			item.target = self;
			[menu addItem:item];
		} else {
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Add Additional Peak" action:@selector(attachAdditionalFragment:) keyEquivalent:@""];
			item.target = self;
			[menu addItem:item];
			return menu;
		}
	}
	return nil;
}

# pragma mark - tracking area and geometry


- (void)updateTrackingArea {
	[self reposition];			/// our view doesn't reposition us during geometry change, so we reposition here.
	[super updateTrackingArea];
}


- (void)removeTrackingArea {
	[super removeTrackingArea];
	[self removeTooltip];
}


- (void)removeTooltip {
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
}


-(void)setFrame:(NSRect)frame {
	_frame = frame;
	if(layer) {
		layer.bounds = frame;
		layer.position = frame.origin;
	}
}



# pragma mark - drawing and appearance

- (BOOL)layer:(CALayer *)layer shouldInheritContentsScale:(CGFloat)newScale fromWindow:(NSWindow *)window {
	return YES;
}

- (NSString *)description {
	/// used for the tooltip
	BOOL noSizing = trace.chromatogram.sizingQuality.floatValue == 0;
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
	if(layer == dragLineLayer) {
		return NSNull.null;
	}
	return [super actionForLayer:layer forKey:event];
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
		
		/// we prepare the layer that draws the handle.
		/// This layer goes from the start point of the drag to the end point, and takes the whole view height
		/// We could make it larger, but performance is better when the layer is not larger than needed
		float distX = ceil(startPoint.x - handlePosition.x);
		float x = distX < 0? startPoint.x : handlePosition.x;
		CGRect frame = CGRectMake(x - 5, 0, fabsf(distX) + 10, view.frame.size.height);
		dragLineLayer.position = frame.origin;
		dragLineLayer.bounds = frame; /// so the layer coordinates match those of its super layer (hence the trace view).
		[dragLineLayer setNeedsDisplay];
		[view scrollRectToVisible:frame];
	}
}


- (void)setHovered:(BOOL)hovered {
	if((hovered != _hovered || (hovered && toolTipTag == 0)) && !(self.dragged && !hovered)) {
		/// a peak label that is dragged keeps its hovered state
		_hovered = hovered;
		TraceView *view = self.view;
		[view labelDidChangeHoveredState:self];
		if(toolTipTag == 0 && hovered && view.showPeakTooltips) {
			toolTipTag = [view addToolTipRect:self.frame owner:self userData:nil];
		}
	}
}


- (void)setDragged:(BOOL)dragged {
	if(dragged != self.dragged) {
		TraceView *view = self.view;
		NSPoint mouseLocation = view.mouseLocation;
		if(dragged) {
			if(!view.showDisabledBins) {
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
			
			marker = self.marker;
			if(marker.bins.count == 0) {
				return;
			}
			
			for(RegionLabel *markerLabel in view.markerLabels) {
				if(markerLabel.region == marker) {
					if(markerLabel.binLabels.count == 0) {
						return;
					}
					break;
				}
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
			if(NSPointInRect(mouseLocation, view.bounds)) {
				[self attachAllelesWithBin:targetBinLabel.region];
			}
		}
		_dragged = dragged;
	}
}


/// Names alleles that are at our peak after a bin.
///
/// The method may move alleles at our peak (give them the peak scan) before naming them.
///
/// - Parameter bin: The bin to use for naming. If `nil`, alleles get the "non-binned" name, or no name if the marker has no bins.
-(void) attachAllelesWithBin:(nullable Bin *)bin {
	Mmarker *marker = bin.marker? bin.marker : self.marker;
	NSString *name = bin.name;
	if(!name && marker.bins.count > 0) {
		name = [NSUserDefaults.standardUserDefaults stringForKey:DubiousAlleleName];
		if(!name) {
			name = @"?";
		}
	}
	
	Genotype *genotype = [trace.chromatogram genotypeForMarker:marker];
	if(genotype) {
		/// Every fragment at our peak scan (including our fragment, if any) will be named after the bin.
		int scan = self.scan;
		NSSet *allelesWeTake;
		if(self.fragment.additional) {
			allelesWeTake = [genotype.additionalFragments filteredSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Allele *allele, NSDictionary<NSString *,id> * _Nullable bindings) {
				return allele.scan == scan;
			}]];
		} else {
			/// If we don't host an additional fragment (could be no fragment at all), we also take all unused alleles (of scan 0)
			allelesWeTake = [genotype.assignedAlleles filteredSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Allele *allele, NSDictionary<NSString *,id> * _Nullable bindings) {
				return allele.scan <= 0 || allele.scan == scan;
			}]];
			if(allelesWeTake.count == 0) { /// If there is no such allele, we take the used allele that is closest to our peak.
				Allele *closestAllele;
				int minDist = INT_MAX;
				for(Allele *allele in genotype.assignedAlleles) {
					int alleleScan = allele.scan;
					if(abs(alleleScan - scan) < minDist) {
						minDist = abs(alleleScan - scan);
						closestAllele = allele;
					}
				}
				allelesWeTake = [NSSet setWithObject:closestAllele];
			}
		}
		
		for(Allele *allele in allelesWeTake) {
			if(!self.fragment) {
				self.fragment = allele;
			}
			allele.scan = scan;
			allele.name = name;
		}
			
		genotype.status = genotypeStatusManual;
		[self.view.undoManager setActionName:@"Edit Genotype"];
	}
}


/// draws the handle during drag
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)context {
	if(layer == dragLineLayer) {
		if(!self.dragged) {
			/// This removes the handle after being dragged
			return;
		}
		CGContextSetStrokeColorWithColor(context, NSColor.grayColor.CGColor);
		CGContextSetFillColorWithColor(context, NSColor.grayColor.CGColor);

		NSPoint start = startPoint;
		CGRect origin = CGRectMake(start.x-4,start.y -4, 8, 8);
		
		NSPoint endPoint = handlePosition;
		float maxY = NSMaxY(self.view.bounds) -18;
		if(endPoint.y > maxY) {
			endPoint.y = maxY;
		} else if(endPoint.y < 2) {
			endPoint.y = 2;
		}
		endPoint.y += 2;
				
		CGRect current = CGRectMake(endPoint.x-4, endPoint.y-4, 8, 8);
		
		CGContextFillEllipseInRect(context, origin);
		
		CGContextFillEllipseInRect(context, current);
		
		CGContextSetLineWidth(context, 1.5);
		
		CGPoint points[] = {start, endPoint};
		CGContextStrokeLineSegments(context, points, 2);
		
	}
}


# pragma mark - other

-(void)attachAdditionalFragment:(id)sender {
	Mmarker *marker = self.marker;
	if(marker) {
		Genotype *genotype =  [trace.chromatogram genotypeForMarker:marker];
		if(genotype) {
			Allele *newFragment = [[Allele alloc] initWithGenotype:genotype additional:YES];
			if(newFragment) {
				newFragment.scan = self.scan;
				[newFragment findNameFromBins];
				genotype.status = genotypeStatusManual;
				[self.view.undoManager setActionName:@"Add Additional Peak"];
			}
		}
	}
}


/// Removes the fragments(s) at our scan.
- (void)removeFragment:(id)sender {
	LadderFragment *ourFragment = self.fragment;
	if(!ourFragment) {
		return;
	}
	if(trace.isLadder) {
		/// If we have a ladder fragment, we remove it from sizing.
		ourFragment.scan = 0;
		[trace.chromatogram computeFitting];
		[self.view.undoManager setActionName:@"Remove Ladder Size"];
	} else {
		Allele *ourAllele = (Allele *)ourFragment;
		Genotype *genotype = ourAllele.genotype;
		for(Allele *allele in genotype.alleles.copy) {
			if(allele.scan == self.scan) {
				/// We remove any fragments at our scan (ours included). We assume that the user wants to remove all alleles at the peak
				if(allele.additional) {
					[allele removeFromGenotypeAndDelete];
				} else {
					allele.scan = 0;
				}
			} else if(!ourAllele.additional && !allele.additional) {
				/// If there is another valid allele at the genotype, we make a homozygote with our allele
				ourAllele.scan = allele.scan;
				ourAllele.name = allele.name;
				break;
			 }
		 }
		genotype.status = genotypeStatusManual;
		[self.view.undoManager setActionName:@"Edit Genotype"];
	}
	
	self.fragment = nil;
}


/// Allows the user to assign/detach an allele to the peak we represent
- (void)doubleClickAction:(id)sender {
	Mmarker *marker = self.marker;
	LadderFragment *fragment = self.fragment;
	if(fragment) {
		/// if we have an fragment at our peak, we remove it
		[self removeFragment:sender];
	} else if(marker) {
		/// else if we are in a marker range, we find an an allele (or alleles) to add to our peak
		Bin *ourBin;		/// we attach it to the bin at our position, if any
		float ourSize = self.size;
		for(Bin *bin in marker.bins) {
			if(bin.start <= ourSize && bin.end >= ourSize) {
				ourBin = bin;
				break;
			}
		}
		[self attachAllelesWithBin:ourBin];
	}
}





@end
