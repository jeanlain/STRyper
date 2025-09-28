//
//  FragmentLabel.m
//  STRyper
//
//  Created by Jean Peccoud on 02/11/12.
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


#import "FragmentLabel.h"
#import "PeakLabel.h"
#import "LadderFragment.h"
#import "SizeStandard.h"
#import "TraceView.h"
#import "Allele.h"
#import "Genotype.h"
#import "Mmarker.h"
@import Accelerate;

@interface FragmentLabel ()

/// The vertical offset to the original position by which the label has moved down to avoid clipping by the top edge of the view.
@property (nonatomic, readonly) CGFloat yOffset;


@end


							
typedef NS_ENUM(NSUInteger, FragmentLabelType) {
	noTypeFragmentLabel,		/// the default type for a label that is not yet initialized
	ladderFragmentLabel,		/// for a label that represents a ladder fragment
	alleleLabel,				/// for a label that represents an allele
	additionalFragmentLabel,	/// for a label that represents an additional fragment at a marker
	compactAlleleLabel			/// for an allele label this is represented as a dot
} ;


@implementation FragmentLabel {
	FragmentLabelType type;					/// the type of label is not set externally, but by the designated initializer.
											/// It is merely a shortcut that tells whether the fragment the label represents is a ladder fragment or an allele.
	CATextLayer *stringLayer;			  	/// shows the label name or size. It is separate from the base layer because the string is vertically centered,
											/// which isn't possible in a `CATextLayer` without subclassing
	
	BOOL needsUpdateString;					/// Whether the labels needs to change its string, which involves changing its size.
	BOOL needsUpdateStringColor;			/// Whether the labels needs to update its string color.
	BOOL needsUpdateBackgroundColor;		/// Whether the labels needs to update its background color.
	BOOL needsUpdateFont;					/// Whether the labels needs to update the string font.

	/// ivars used for dragging the label
	__weak PeakLabel *destination;		 	/// the peak label that is the possible destination of the fragment label being dragged
	CGFloat refDist;							/// The maximum distance allowed between the destination and the dragged label.
											/// It depends on the label width.
	
	NSTimer *clickedTimer;					/// A timer used to set the dragged state of the label has been clicked for a long time
	BOOL draggedOut;						/// Whether the label is being dragged out of the view (above the top edge)
					
	/// We use this ivar to force animating ladder fragment labels that have been
	/// dragged to other peaks. This operation changes sample sizing, which resizes the host view,
	/// normally preventing animation of labels. But we want to give better feedback to the user about
	/// the labels that has been affected by the drag.
	BOOL forceAnimations;

}


# pragma mark - init and attributes

/// We observe some keys of the fragment to update when they change
static NSString * const fragmentScanKey = @"fragment.scan";
static NSString * const fragmentStringKey = @"fragment.string";
static NSString * const fragmentOffsetKey = @"fragment.offset";
static NSString * const fragmentSizeKey = @"fragment.size";

static void * const fragmentScanChangedContext = (void*)&fragmentScanChangedContext;
static void * const fragmentStringChangedContext = (void*)&fragmentStringChangedContext;
static void * const fragmentOffsetChangedContext = (void*)&fragmentOffsetChangedContext;
static void * const fragmentSizeChangedContext = (void*)&fragmentSizeChangedContext;


- (instancetype)init {
	return [self initFromFragment:nil view:nil compact:NO];
}


- (instancetype)initFromFragment:(LadderFragment *)fragment view:(TraceView *)view compact:(BOOL)compact {
	self = [super init];
	if (self) {
		forceAnimations = NO;
		layer = CALayer.new;
		layer.delegate = self;
		layer.cornerRadius = compact? 3 : 2;
		layer.borderColor = [NSColor colorWithCalibratedRed:0.4 green:0.6 blue:0.9 alpha:1].CGColor;
		
		if(!compact) {
			stringLayer = CATextLayer.new;
			stringLayer.delegate = self;
			stringLayer.fontSize = 9.0;
			stringLayer.contentsScale = 3.0; /// This makes text sharper even if the display is 2X (a 1X display requires 2X).
			stringLayer.alignmentMode = kCAAlignmentCenter;
			stringLayer.truncationMode = kCATruncationEnd;
			[layer addSublayer:stringLayer];
			
			[self addObserver:self forKeyPath:fragmentScanKey options:NSKeyValueObservingOptionNew context:fragmentScanChangedContext];
			[self addObserver:self forKeyPath:fragmentStringKey options:NSKeyValueObservingOptionNew context:fragmentStringChangedContext];
			[self addObserver:self forKeyPath:fragmentOffsetKey options:NSKeyValueObservingOptionNew context:fragmentOffsetChangedContext];
		} else {
			type = compactAlleleLabel;
			layer.bounds = CGRectMake(0, 0, 6, 6);
			_frame = layer.frame;
			[self addObserver:self forKeyPath:fragmentSizeKey options:NSKeyValueObservingOptionNew context:fragmentSizeChangedContext];
		}	
		
		self.fragment = fragment;
		self.view = view;
	}
	return self;
}


- (BOOL)isCompact {
	return type == compactAlleleLabel;
}


- (id)representedObject {
	return self.fragment;
}


- (BOOL)tracksMouse {		
	/// This label does not react when it is hovered.
	return NO;
}


- (void)setFragment:(LadderFragment *)fragment {
	_fragment = fragment;
	if(fragment) {
		if(type != compactAlleleLabel) {
			FragmentLabelType previousType = type;
			if([fragment isKindOfClass:Allele.class]) {
				type = fragment.additional? additionalFragmentLabel : alleleLabel;
			} else {
				type = ladderFragmentLabel;
			}
			if(previousType != type) {
				needsUpdateFont = YES;
			}
		}
		needsUpdateBackgroundColor = YES; /// The color also depends on the channel, not just the type of fragment
		self.needsUpdateAppearance = YES;
	}
}


- (void)setView:(TraceView *)aView {
	if(self.view) {
		if(alleleNameTextField.delegate == self) {
			alleleNameTextField.hidden = YES;
		}
	}
	super.view = aView;
	if(layer && aView.backgroundLayer) {
		[aView.backgroundLayer addSublayer:layer];
	}
}


- (void)removeFromView {
	if(clickedTimer.isValid) {
		[clickedTimer invalidate];
	}
	[super removeFromView];
}


# pragma mark - changes in appearance

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if(context == fragmentScanChangedContext || context == fragmentSizeChangedContext) {
		TraceView *view = self.view;
		if(view) {
			forceAnimations = view.allowsAnimations;
			if(!view.needsRepositionFragmentLabels) {
				[view labelNeedsRepositioning:self];
			}
			if(type == ladderFragmentLabel) {
				needsUpdateBackgroundColor = YES; /// The background color depends on whether the scan is 0.
				self.needsUpdateAppearance = YES;
			}
		}
	} else if(context == fragmentStringChangedContext) {
		if(![self.fragment.string isEqualToString:stringLayer.string]) {
			needsUpdateString = YES;
			TraceView *view = self.view;
			if(view && !view.needsRepositionFragmentLabels) {
				/// We change the string during `-reposition` as it affects the size of the label
				[view labelNeedsRepositioning:self];
			}
		}
	} else if(context == fragmentOffsetChangedContext) {
		needsUpdateStringColor = YES;
		self.needsUpdateAppearance = YES;
	} 
}


- (void)updateAppearance {
	layer.borderWidth = self.highlighted?  2.0 : 0.0; /// the border becomes visible when the label is highlighted
													  
	if(type == compactAlleleLabel) {
		[self moveCloser:self.highlighted];
	} else {
		[self moveCloser:self.dragged];
	}
	
	if(needsUpdateBackgroundColor) {
		[self updateBackgroundColor];
	}
	
	if(needsUpdateStringColor) {
		[self updateStringColor];
	}
	
	if(needsUpdateFont) {
		stringLayer.font = type == alleleLabel? (__bridge CFTypeRef _Nullable)([NSFont boldSystemFontOfSize:9]) :
		(__bridge CFTypeRef _Nullable)([NSFont labelFontOfSize:9]);
		needsUpdateFont = NO;
	}
}


/// Update or sets the appropriate string color, which depends on our type, or offset of our fragment
- (void)updateStringColor {
	stringLayer.foregroundColor = NULL;
	TraceView *view = self.view;
	if(type == ladderFragmentLabel) {
		/// We denote our fragment's offset by the level of red in the string
		/// I haven't found a function that blends CGColorRef colors. Converting to NSColor would be simpler but probably less efficient.
		CGColorRef stringColor =  view.labelStringColor;
		CGColorSpaceRef space = CGColorGetColorSpace(stringColor);
		if(CGColorSpaceGetModel(space) == kCGColorSpaceModelRGB) {
			const CGFloat *components = CGColorGetComponents(stringColor);
			CGFloat redComponents[] = {1, 0, 0, 1};
			/// The fraction of red depends on the original color. It's higher when it is white.
			float fraction = components[0] > 0.9 ? fabs(self.fragment.offset)/20 : fabs(self.fragment.offset)/10;
			for (int i = 0; i < 4; i++) {
				redComponents[i] = fraction * redComponents[i] + (1 - fraction) * components[i];
			}
			CGColorRef color = CGColorCreate(space, redComponents);
			stringLayer.foregroundColor = color;
			CGColorRelease(color);
		}
	} else if(type == alleleLabel) {
		stringLayer.foregroundColor = NSColor.whiteColor.CGColor;
	} else {
		stringLayer.foregroundColor = view.labelStringColor;
	}
	needsUpdateStringColor = NO;
}



-(void) updateBackgroundColor {
	layer.backgroundColor = NULL;
	if(!self.enabled) {
		layer.backgroundColor = NSColor.lightGrayColor.CGColor;
	} else {
		TraceView *view = self.view;
		if(view) {
			if(type == alleleLabel || type == compactAlleleLabel) {
				layer.backgroundColor = view.alleleLabelBackgroundColor;
			} else if(self.fragment.scan > 0) {
				layer.backgroundColor = view.fragmentLabelBackgroundColor;
			} else {
				/// For a label that represents a ladder fragment that is unused.
				layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.5 alpha:0.7].CGColor;
			}
		}
	}
	needsUpdateBackgroundColor = NO;
}


- (void)updateForTheme {
	[self updateStringColor];
	[self updateBackgroundColor];
}


- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
	if((forceAnimations || self.view.allowsAnimations) && _allowsAnimations && ([event isEqualToString:@"position"] || [event isEqualToString:@"bounds"])) {
		return nil;
	}
	return NSNull.null;
}

# pragma mark - dragging behavior

- (void)mouseDraggedInView {
	if(type != compactAlleleLabel) { /// compact labels cannot be dragged
		[super mouseDraggedInView];
	}
}


-(void)drag {
	TraceView *view = self.view;
	NSPoint mouseLocation = view.mouseLocation;
	
	if(!self.dragged) {
		/// We do not start the drag if the user has not dragged the mouse for at least 5 points.
		/// This avoids assigning the peak to an allele for what could be a simple click
		NSPoint clickedPoint = view.clickedPoint;
		CGFloat dist = pow(pow(mouseLocation.x - clickedPoint.x, 2.0) + pow(mouseLocation.y - clickedPoint.y, 2.0), 0.5);
		if(dist < 5) {
			return;
		}
		self.dragged = YES;
	}
	
	/// The user can drag a label out (over the top edge) to remove the label.
	if(mouseLocation.y > NSMaxY(view.bounds) + 2) {
		if(!draggedOut) {
			draggedOut = YES;
			if(self.fragment.scan > 0) {
				[NSCursor.disappearingItemCursor push];
			}
		}
	} else if(draggedOut) {
		draggedOut = NO;
		[NSCursor.currentCursor pop];
	}
	
	/// We determine the peak that is the closest to the label
	CGFloat minDist = INFINITY;
	PeakLabel *closestPeak;
	for(PeakLabel *peakLabel in view.peakLabels) {
		CGFloat dist = fabs(mouseLocation.x - [view xForScan:peakLabel.scan ofSample:self.fragment.trace.chromatogram]);
		if(dist < minDist) {
			minDist = dist;
			closestPeak = peakLabel;
		} else {
			break; /// Because peak labels are ordered by increasing scan (hence sizes).
		}
	}
	
	if(minDist > refDist || draggedOut) {
		destination.hovered = NO;
		destination = nil;
	} else if(destination != closestPeak && [self canMoveToPeakLabel:closestPeak]) {
		destination.hovered = NO;
		destination = closestPeak;
		closestPeak.hovered = YES;
		/// We signify a new destination with haptic feedback
		[NSHapticFeedbackManager.defaultPerformer performFeedbackPattern:NSHapticFeedbackPatternAlignment
														 performanceTime:NSHapticFeedbackPerformanceTimeDefault];
	}
	[self reposition];
	[super drag];
}


- (void)setEnabled:(BOOL)enabled {
	if(enabled != _enabled) {
		needsUpdateBackgroundColor = YES;
		super.enabled = enabled;
	}
}


- (void)setClicked:(BOOL)clicked {
	/// If the label is clicked for 1 sec, we consider it dragged (which changes its appearance).
	if(clicked != self.clicked) {
		[super setClicked:clicked];
		if(clicked) {
			clickedTimer = [NSTimer scheduledTimerWithTimeInterval:0.7 
															target:self
														  selector:@selector(clickedLong) 
														  userInfo:nil
														   repeats:NO];
		} else {
			if([clickedTimer isValid]) {
				[clickedTimer invalidate];
			}
		}
	}
}


-(void)clickedLong {
	self.dragged = YES;
}


- (void)setDragged:(BOOL)dragged {
	if(dragged != _dragged) {
		_dragged = dragged;
		if(dragged) {
			draggedOut = NO;
			refDist = self.frame.size.width /2;
			if(refDist > 15) {
				refDist = 15;
			}
			
			int scan = self.fragment.scan;
			if(scan > 0) {
				for(PeakLabel *peakLabel in self.view.peakLabels) {
					if(peakLabel.scan == scan) {
						destination = peakLabel;
						break;
					}
				}
			}
		
		} else {
			if(draggedOut) {
				if(self.fragment.scan > 0) {
					[self removeFragment:self]; /// Which repositions the label at the top of the view at the theoretical size.
				} else {
					[self.view labelNeedsRepositioning:self];
				}
				draggedOut = NO;
				[NSCursor.currentCursor pop];
			} else {
				[self takeDestinationPeak];
			}
		}
		self.needsUpdateAppearance = YES;
	}
}


/// Change the Z position of the label such that it appears closer.
/// - Parameter closer: Wether the label should appear closer. If `NO`, the label takes its normal scale.
-(void)moveCloser:(BOOL)closer {
	if(closer) {
		layer.zPosition = 2.0;
		layer.shadowOpacity = 0.5;
		layer.shadowRadius = 5.0;
		layer.shadowOffset = CGSizeMake(0, -3);
		float factor = type == compactAlleleLabel? 1.5 : 1.2;
		layer.transform = CATransform3DMakeScale(factor, factor, 1);
	} else {
		layer.zPosition = 0.0;
		layer.shadowOpacity = 0;
		layer.shadowRadius = 0;
		layer.transform = CATransform3DIdentity;
	}
}


/// Wether the label can be moved to a peak label.
/// - Parameter label: The peak label to test.
-(BOOL)canMoveToPeakLabel:(PeakLabel *)label {
	
	if(!label) {
		return NO;
	}
		
	if(type != ladderFragmentLabel) {
		Allele *allele = self.fragment;
		Mmarker *marker = allele.genotype.marker;
		float peakPos = label.size;
		if(peakPos > marker.end || peakPos < marker.start) {
			/// The peak cannot take the label if is not in the marker range.
			return NO;
		}
		Allele *destinationAllele = label.fragment;
		if(destinationAllele && allele.additional && !destinationAllele.additional) {
			/// A non-additional allele cannot take a peak occupied by an assigned allele.
			return NO;
		}
		return YES;
	} else {
		int peakScan = label.scan;
		float size = self.fragment.size;
		for(FragmentLabel *sizeLabel in self.view.fragmentLabels) {
			LadderFragment *sizeFragment = sizeLabel.fragment;
			int sizeFragmentScan = sizeFragment.scan;
			float sizeFragmentSize = sizeFragment.size;
			if(sizeFragmentScan > 0) {
				if(sizeFragmentSize < size && peakScan < sizeFragmentScan) {
					/// A peak that is at the left of a peak assigned to a given size cannot take a size that is larger.
					return NO;
				}
				if(sizeFragmentSize > size && peakScan > sizeFragmentScan) {
					/// A peak that is at the right of a peak assigned to a given size cannot take a size that is shorter.
					return NO;
				}
			}
		}
		return YES;
	}
	
	return NO;
}



-(void) takeDestinationPeak {
	LadderFragment *fragment = self.fragment;
	if(destination.scan == fragment.scan || ![self canMoveToPeakLabel:destination]) {
		/// if the destination is the same as the peak we already have or can't take the label (if nil for instance),
		/// we just need to return to our original position.
		[self.view labelNeedsRepositioning:self];
		return;
	}
	
	TraceView *view = self.view;
	LadderFragment *destinationFragment = destination.fragment;
	
	if(destinationFragment && type == ladderFragmentLabel) {
		/// if the destination already has a ladder fragment, we de-assign it.
		destinationFragment.scan = 0;
		destinationFragment.offset = 0.0;
	}
	
	/// we give our fragment the scan of the destination.
	fragment.scan = destination.scan;
	
	if(type == ladderFragmentLabel) {
		[fragment.trace.chromatogram computeFitting];
		[view.undoManager setActionName:@"Reassign Ladder Size"];
	} else {
		Allele *allele = (Allele *)fragment;
		if(destinationFragment.name) {
			/// our allele takes the name of the destination, creating a homozygote
			fragment.name = destinationFragment.name;
		} else {
			/// our allele takes the name of the bin at the destination (if any)
			[allele findNameFromBins];
		}
		if(!fragment.additional) {
			/// A "true" allele removes all additional fragments at its destination.
			Genotype *genotype = ((Allele *)fragment).genotype;
			for(Allele *allele in genotype.additionalFragments) {
				if(allele.scan == fragment.scan) {
					[allele removeFromGenotypeAndDelete];
				}
			}
		}
		allele.genotype.proposedStatus = genotypeStatusManual;
		[view.undoManager setActionName:@"Edit Genotype"];
	}
}

# pragma mark - geometry

static int const topMargin = 10; /// The minimum distance between a fragment label and the top of the view

- (void)reposition {
	_yOffset = 0;
	TraceView *view = self.view;
	LadderFragment *fragment = self.fragment;
	Trace *trace = fragment.trace;
	
	if (self.hidden || view.hScale <= 0.0 || !trace)  {
		/// These are safety measures that may no longer be required. TO CHECK.
		return;
	}
	
	if(needsUpdateString) {
		[self updateString];
	}
	
	NSRect viewBounds = view.bounds;
	NSRect frame = self.frame;
	CGFloat frameWidth = frame.size.width;
	CGFloat frameHeight = frame.size.height;
	CGFloat yAnchor = 0; /// The distance between the anchor point of the layer and the bottom of the frame
	int fragmentScan = fragment.scan;
	
	NSPoint location;
	if(!self.dragged) {
		if(fragmentScan > 0) {
			location.y = [view yForScan:fragmentScan ofTrace:trace];
			if(type != compactAlleleLabel) {
				/// we position ourself a bit higher than the peak tip
				location.y += 4.0;
				location.x = [view xForScan:fragmentScan ofSample:trace.chromatogram];
			} else {
				location.x = [view xForSize:fragment.size];
				yAnchor = frameHeight/2;
			}
		} else {
			/// In this case, our fragment is "deleted"
			if(type == ladderFragmentLabel) {
				/// for a ladder fragment, we position ourselves at the top of the view and exactly at our size in base pairs
				location = NSMakePoint([view xForSize: fragment.size], NSMaxY(viewBounds) - frameHeight);
			} else {
				/// For an deleted allele, we position above our view (higher than its frame), at the midpoint of the marker range
				Mmarker *marker = ((Allele *)fragment).genotype.marker;
				float midSize = (marker.end + marker.start)/2;
				_yOffset = -1000;  /// We use this offset do denote that the label need not check for collisions with others
				location = NSMakePoint([view xForSize:midSize], NSMaxY(viewBounds) + 20);
			}
		}
	} else {
		location = view.mouseLocation;
		if(destination) {
			location.x = [view xForScan:destination.scan ofSample:trace.chromatogram];
		}
		/// We want the label to be centered behind the cursor during drag.
		/// So we make is if the cursor location was lower by half the height of the label
		CGFloat halfHeight = frameHeight/2;
		if(location.y < halfHeight) {
			location.y = halfHeight;
		}
		location.y -= halfHeight;
	}
	
	CGFloat margin = draggedOut? -3:topMargin;
	
	NSRect newFrame = NSMakeRect(location.x - frameWidth/2, location.y - yAnchor, frameWidth, frameHeight);
	
	if(fragmentScan > 0 || self.dragged) {
		CGFloat delta =  NSMaxY(view.bounds) - margin - NSMaxY(newFrame); /// prevents the label from being clipped by the view
		if (delta < 0) {
			_yOffset = -delta;
			newFrame.origin.y += delta;
		}
	}
	
	self.frame = newFrame;
	forceAnimations = NO;
}


- (void)setFrame:(NSRect)rect {
	_frame = rect;
	layer.position = CGPointMake(NSMidX(rect), NSMidY(rect));
	/// if the textfield allowing to edit the name is shown, we must move it in concert.
	if(alleleNameTextField.delegate == self && alleleNameTextField.superview) {
		/// we set its middle x position the same as ours
		[alleleNameTextField setFrameOrigin:NSMakePoint(rect.origin.x + rect.size.width/2 - alleleNameTextField.frame.size.width/2, rect.origin.y)];
	}
}


-(void)updateString {
	if (alleleNameTextField.delegate == self) {
		alleleNameTextField.hidden = YES;
	}
	
	/// We compute the the frame size, which depends on the string shown, but also on the font.
	if(needsUpdateFont) {
		stringLayer.font = type == alleleLabel? (__bridge CFTypeRef _Nullable)([NSFont boldSystemFontOfSize:9]) :
		(__bridge CFTypeRef _Nullable)([NSFont labelFontOfSize:9]);
		needsUpdateFont = NO;
	}

	stringLayer.string = self.fragment.string;
	NSSize size = stringLayer.preferredFrameSize;
	/// We constrain the string width between 15 and 50.
	CGFloat width = MAX(size.width, 15.0);
	width = MIN(50, width);
	CGRect bounds = CGRectMake(0, 0, width + 2, size.height + 2);
	layer.bounds = bounds;
	_frame = layer.frame;
	stringLayer.bounds = CGRectMake(0, 0, width, size.height);
	stringLayer.position = CGPointMake(NSMidX(bounds), NSMidY(bounds));
	needsUpdateString = NO;
}



/// Returns whether two rectangles overlap on their horizontal dimension.
/// - Parameters:
///   - rectA: A rectangle.
///   - rectB: A rectangle.
bool overlapXRects(NSRect rectA, NSRect rectB) {
	return NSMaxX(rectA) > rectB.origin.x && rectA.origin.x < NSMaxX(rectB);
}




+(void) avoidCollisionsInView:(TraceView *)view {

	
	NSPredicate	*filterPredicate = [NSPredicate predicateWithBlock:^BOOL(FragmentLabel *label, NSDictionary<NSString *,id> * _Nullable bindings) {
			return label.yOffset > -800;
		}];
	
	NSArray<FragmentLabel *> *fragmentLabels = [view.fragmentLabels filteredArrayUsingPredicate: filterPredicate];
	
	NSInteger labelCount = fragmentLabels.count;
	if(labelCount < 2) {
		return;
	}
	
	CGFloat ceiling = NSMaxY(view.bounds) - (view.trace.isLadder? 0 : topMargin); /// The maximum position of a top edge of a label.
	
	/// We determine alleles that overlap along the X axis. For this, we sort labels by the x coordinates of their frame's origin.
	fragmentLabels = [fragmentLabels sortedArrayUsingComparator:^NSComparisonResult(FragmentLabel *label1, FragmentLabel *label2) {
		if(label1.frame.origin.x < label2.frame.origin.x) {
			return NSOrderedAscending;
		}
		return NSOrderedDescending;
	}];
	
	CGFloat maxX = -INFINITY;  /// The largest X coordinate of the frame of the current label.
	vDSP_Length nOverlaps = 0; /// number of labels that overlap along the x axis (-1)
	NSRect *frames = malloc(labelCount * sizeof(NSRect)); /// Their frames
	CGFloat *yOrigins = malloc(labelCount * sizeof(CGFloat));	/// The origin of their frame (on the Y axis), which will be used for sorting
	vDSP_Length *indices = malloc(labelCount * sizeof(vDSP_Length)); /// indices used for sorting

	int i = 0;
	for(FragmentLabel *label in fragmentLabels) {
		NSRect frame = label.frame;
		if(frame.origin.x > maxX) {
			/// The label does not overlap with the current group (of overlapping labels), which indicates the end of the group
			if(nOverlaps >=1) {
				spreadLabels(frames, indices, yOrigins, nOverlaps+1, fragmentLabels, i-nOverlaps-1, ceiling);
			}
			nOverlaps = 0;
		} else {
			nOverlaps++;
		}
		frames[nOverlaps] = frame;
		indices[nOverlaps] = nOverlaps;
		yOrigins[nOverlaps] = frame.origin.y + label.yOffset;
		maxX = MAX(NSMaxX(frame), maxX);
		i++;
	}
	
	if(nOverlaps >= 1) {
		/// For the the last group
		spreadLabels(frames, indices, yOrigins, nOverlaps+1, fragmentLabels, i-nOverlaps-1, ceiling);
	}
	
	free(frames);
	free(yOrigins);
	free(indices);
}


void spreadLabels(NSRect *frames, vDSP_Length* indices, CGFloat *yOrigins, vDSP_Length frameCount, NSArray *labels, vDSP_Length start, CGFloat ceiling) {
	/// We sort the frames by ascending Y origin.
	vDSP_vsortiD(yOrigins, indices, NULL, frameCount, 1);
	
	CGFloat maxY = 0; /// Will be the top edge position of the highest label, which we will use to determine it we must move labels down given the height of the view.
	CGFloat *yOffsets = malloc(frameCount * sizeof(CGFloat)); /// The vertical distance by which a label will be moved
	yOffsets[0] = 0;	   /// We don't reposition the first label (bottom one).
	CGFloat lowestY = frames[indices[0]].origin.y;
	
	for (int i = 1; i < frameCount; i++) {
		yOffsets[i] = 0;
		NSRect *frameI = &frames[indices[i]]; /// The frame that may be moved vertically to avoid a collision.
		
		/// We go through frames that are (were)  lower than `frameI` to check which overlap / intersect with it.
		long topOverlapRect = -1;  /// The index of the highest frame that overlaps.
		CGFloat topOverlapY = 0;	   /// The top edge of its frame.
		CGFloat minOverlapY = INFINITY;  /// The bottom edge position of the lowest frame that overlaps.
		BOOL intersects = NO;		/// Whether a frame intersects with frameI.
		for (int j = 0; j < i; j++) {
			NSRect *frameJ = &frames[indices[j]];
			if(overlapXRects(*frameI, *frameJ)) {
				CGFloat y = NSMaxY(*frameJ);
				if(y > topOverlapY) {
					topOverlapY = y;
					topOverlapRect = j;
				}
				if(frameJ->origin.y < minOverlapY) {
					minOverlapY = frameJ->origin.y;
				}
				if(!intersects) {
					intersects = NSIntersectsRect(*frameI, *frameJ);
				}
			}
		}
		
		if(intersects) {  /// We have to move `frameI` to avoid a collision.
			CGFloat originalY = frameI->origin.y;
			if((yOffsets[topOverlapRect] < 0.1)) {
				/// if the highest overlapping frame has not been moved up, we move the current frame up.
				frameI->origin.y = topOverlapY;
			} else {
				/// Otherwise, we try to move it down to avoid spreading labels too much on the vertical axis.
				/// To be safe, we try to go bellow the lowest frame that overlaps (this may not be optimal if there is room between overlapping labels
				/// on the vertical axis, but it works well enough).
				CGFloat newOrigin = minOverlapY - frameI->size.height;
				if(minOverlapY > lowestY && newOrigin > 0 && (originalY - newOrigin) < (topOverlapY - originalY)) {
					/// But we don't go this far down if the distance is greater than what were needed if we moved up.
					frameI->origin.y = newOrigin;
				} else {
					frameI->origin.y = topOverlapY;
				}
			}
			yOffsets[i] = frameI->origin.y - originalY;
		}
		CGFloat topY = NSMaxY(*frameI);
		if(maxY < topY) {
			maxY = topY;
		}
	}
	free(yOffsets);
	
	CGFloat excessY = maxY - ceiling;
	if(excessY > 0) {
		/// If a frame has moved too far up, we sort frames by decreasing height, as we will move them down while maintaining the relative vertical order.
		/// We don't move them all down by `excessY` as some may not need to be moved (the do only if they are "pushed" by others).
		for (vDSP_Length i = 0; i < frameCount; i++) {
			yOrigins[i] = frames[i].origin.y;
			indices[i] = i;
		}
		vDSP_vsortiD(yOrigins, indices, NULL, frameCount, -1);
		/// We already move the top frame down as necessary
		frames[indices[0]].origin.y -= excessY;
		
		/// We check the other frames if they need to be moved down.
		for (int i = 1; i < frameCount; i++) {
			NSRect *frame = &frames[indices[i]];
			maxY = ceiling; /// The maximum Y position of the frame
			for (int j = i-1; j >= 0; j--) {
				/// We enumerate frames that have been already adjusted
				NSRect *frameJ = &frames[indices[j]];
				if(overlapXRects(*frame, *frameJ)) {
					/// If one overlaps with the current frame, its bottom position is the maximum top position of the current frame
					maxY = frameJ->origin.y;
					break;
				}
			}
			CGFloat newOrigin = maxY - frame->size.height;
			if(frame->origin.y > newOrigin) {
				frame->origin.y = newOrigin;
			}
		}
	}
	
	for (int i = 0; i < frameCount; i++) {
		FragmentLabel *label = labels[i+start];
		label.frame = frames[i];
	}
}


# pragma mark - other user actions

- (NSMenu *)menu {
	NSMenu *menu;
	if(self.fragment.scan > 0) {
		
		menu = NSMenu.new;
		NSMenuItem *item;
		if(type != compactAlleleLabel) {
			if(type != ladderFragmentLabel) {
				item = [[NSMenuItem alloc] initWithTitle:@"Rename"
												  action:@selector(showAlleleNameTextFieldAfterDelay:)
						/// Delay necessary as the presence of the menu exits editing of the text field.
													   keyEquivalent:@""];
				item.target = self;
				[menu addItem:item];
			}
			NSString *title = type == ladderFragmentLabel? @"Remove Size" : @"Delete";
			item = [[NSMenuItem alloc] initWithTitle:title action:@selector(removeFragment:)
												   keyEquivalent:[NSString stringWithFormat:@"%c",NSBackspaceCharacter]];
			item.keyEquivalentModifierMask = 0;
		} else {
			item = [[NSMenuItem alloc] initWithTitle:@"View Chromatogram" action:@selector(isolateAllele:)
												   keyEquivalent:@""];
			item.offStateImage = [NSImage imageNamed:ACImageNameCallAllelesBadge];
		}
		item.target = self;
		[menu addItem:item];
	}
	return menu;
}



- (void)deleteAction:(id)sender {
	if(!_dragged && type != compactAlleleLabel) {
		[self removeFragment:sender];
	}
}


- (NSString *)deleteActionTitle {
	switch (type) {
		case alleleLabel:
			return @"Delete Allele";
		case additionalFragmentLabel:
			return @"Delete Label";
		case ladderFragmentLabel:
			return @"Remove Ladder Size";
		default:
			return nil;
	}
}


- (void)removeFragment:(id)sender {
	LadderFragment *fragment = self.fragment;
	if(!fragment || fragment.scan <= 0) {
		return;
	}
	
	/// As we may be removed from the view when the fragment is removed, we keep reference to the undo manager
	NSUndoManager *undoManager = self.view.undoManager;
	if(type != additionalFragmentLabel) {
		fragment.scan = 0;		/// which will reposition the label
	}
	if(type == ladderFragmentLabel) {
		/// the user wants to remove our ladder fragment from sizing
		/// we need to recompute sizing as the fragments have changed
		[fragment.trace.chromatogram computeFitting];
	} else {
		Genotype *genotype = [(Allele *)fragment genotype];
		genotype.proposedStatus = genotypeStatusManual;
		if(type == additionalFragmentLabel) {
			[(Allele *)fragment removeFromGenotypeAndDelete];
		}
	}
	[undoManager setActionName: self.deleteActionTitle];
}


-(void)isolateAllele:(id)sender {
	TraceView *view = self.view;
	[view.delegate traceView:view revealSourceItem:self.fragment isolate:YES];
}


static NSTextField *alleleNameTextField;	/// the text field allowing the user to edit the allele name (a ladder fragment size isn't editable)
											/// we use a single instance for all labels since only one can be edited at a time

- (void)doubleClickAction:(id)sender {
	/// we show the text field allowing the user to edit an allele name directly on the trace view
	if(!self.fragment || type == compactAlleleLabel) {
		return;
	}
	
	if(type == ladderFragmentLabel) {
		[self removeFragment:sender];
		return;
	}
	
	[self showAlleleNameTextField];
}


-(void)showAlleleNameTextFieldAfterDelay:(id)sender {
	[self performSelector:@selector(showAlleleNameTextField) withObject:self afterDelay:0];
}


-(void)showAlleleNameTextField {
	if(!alleleNameTextField) {
		alleleNameTextField = NSTextField.new;
		alleleNameTextField.editable = YES;
		alleleNameTextField.bezeled = NO;
		alleleNameTextField.drawsBackground = YES;					/// otherwise, the label itself would show behind the text field
		alleleNameTextField.backgroundColor = self.view.backgroundColor;
		alleleNameTextField.font = [NSFont labelFontOfSize:10];
		alleleNameTextField.alignment = NSTextAlignmentCenter;
		alleleNameTextField.cell.wraps = NO;
	}
	if(alleleNameTextField.delegate != self) {
		[alleleNameTextField bind:NSValueBinding toObject:self withKeyPath:@"fragment.name" options:nil];
		[self.view addSubview:alleleNameTextField];
		alleleNameTextField.delegate = self;
	}
	alleleNameTextField.hidden = NO;
	alleleNameTextField.frame = NSInsetRect(self.frame, -3, 0);
	[alleleNameTextField selectText:self];
	[self.view scrollRectToVisible:alleleNameTextField.frame animate:YES];
	self.highlighted = YES; 	/// we make sure we stay highlighted (the textfield becoming the first responder would make the trace view de-highlight us)
								/// This has some implication for when the textfield disappears, to avoid remaining highlighted.
}

- (void)cancelOperation:(id)sender {
	/// Hides the textField without applying its value to the name of our fragment
	if(!alleleNameTextField.hidden && alleleNameTextField.delegate == self) {
		[alleleNameTextField abortEditing];
		alleleNameTextField.delegate = nil;
		alleleNameTextField.hidden = YES;
	}
}


- (void)controlTextDidChange:(NSNotification *)obj {
	/// We adjust the width of the textfield to the text entered
	NSString *temp = alleleNameTextField.stringValue;
	/// if we don't access the string, the cellSize below is not correct.
	/// There's probably a more elegant solution. We could also compute the attributed string width...

	temp = temp; 													/// to suppress the unused variable warning
	CGFloat newWidth = MIN(150, MAX(alleleNameTextField.cell.cellSize.width, self.frame.size.width + 6));
	NSRect rect = alleleNameTextField.frame;
	rect = NSMakeRect(NSMidX(rect) - newWidth/2, rect.origin.y, newWidth, rect.size.height);
	[alleleNameTextField setFrame:rect];
	[self.view scrollRectToVisible:rect animate:YES];
}


- (void)controlTextDidEndEditing:(NSNotification *)obj {
	if(obj.object == alleleNameTextField) {
		TraceView *view = self.view;
		NSWindow *window = view.window;
		if(window.firstResponder == window) {
			/// when the user validates with the enter key, the first responder becomes the window, but it makes more sense for it to be the view.
			[window performSelector:@selector(makeFirstResponder:) withObject:view afterDelay:0.0];
		} else {
			/// Otherwise, the user must have clicked outside the textfield (hence the label)
			/// In this case the highlighting should not remain.
			/// The view would not do it for us if the user has clicked elsewhere and the view is not the first responder.

			self.highlighted = NO;
		}
		alleleNameTextField.hidden = YES;
		NSString *actionName = type == alleleLabel? @"Rename Allele" : @"Rename Additional Peak";
		[view.undoManager setActionName:actionName];
	}
}


# pragma mark - other

- (void)dealloc {
	if(type != compactAlleleLabel) {
		[self removeObserver:self forKeyPath:fragmentScanKey];
		[self removeObserver:self forKeyPath:fragmentStringKey];
		[self removeObserver:self forKeyPath:fragmentOffsetKey];
	} else {
		[self removeObserver:self forKeyPath:fragmentSizeKey];
	}
}

@end

