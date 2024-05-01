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

/// The fragment labels that overlap on the horizontal axis, used to avoid collisions.
/// These labels contain at least one that overlap with us, and  constitute all labels that are
/// connected by a relation of overlap on the X axis (a single-linkage cluster).
/// These labels are therefore not independent when we reposition them to avoid collisions.
@property (nonatomic) NSMutableSet <FragmentLabel *>* overlappingLabels;

/// Whether some label frames intersect among the `overlappingLabels`
@property (nonatomic, readonly) BOOL intersects;

/// Used to gather the overlapping labels
@property (nonatomic, weak, readonly) FragmentLabel *refLabel;

/// The vertical offset to the original position by which the label has moved down to avoid clipping by the top edge of the view.
@property (nonatomic, readonly) float yOffset;


@end


							
typedef enum FragmentLabelType : NSUInteger {
	noTypeFragmentLabel,		/// the default type for a label that is not yet initialized
	ladderFragmentLabel,		/// for a label that represents a ladder fragment
	alleleLabel,				/// for a label that represents an allele
	additionalFragmentLabel		/// for a label that represents an additional fragment at a marker
} FragmentLabelType;


@implementation FragmentLabel {
	FragmentLabelType type;			/// the type of label is not set externally, but by the designated initializer. It is merely a shortcut that tells whether the fragment the label represents is a ladder fragment or an allele.
	CATextLayer *stringLayer;			  	/// shows the label name or size. It is separate from the base layer because the string is vertically centered,
											/// which isn't possible in a `CATextLayer` without subclassing
	
	BOOL needsUpdateFrameSize;
	
	/// ivars used for dragging the label
	__weak PeakLabel *destination;		 	/// the peak label that is the possible destination of the fragment label being dragged
	float refDist;							/// The maximum distance allowed for the destination
											/// It depends on the label width.
	
	NSTimer *clickedTimer;					/// A timer used to set the dragged state of the label has been clicked for a long time
	BOOL draggedOut;						/// Whether the label is being dragged out of the view (above the top edge)
}

@synthesize yOffset = _yOffset, intersects = _intersects, refLabel = _refLabel;

# pragma mark - init and attributes

static NSArray<NSString *> const *observedKeyPaths;
static void * const fragmentScanChangedContext = (void*)&fragmentScanChangedContext;
static void * const fragmentStringChangedContext = (void*)&fragmentStringChangedContext;
static void * const fragmentOffsetChangedContext = (void*)&fragmentOffsetChangedContext;


+ (void)initialize {
	if (self == [FragmentLabel class]) {
		observedKeyPaths = @[@"fragment.scan", @"fragment.string", @"fragment.offset"];
	}
}


- (instancetype)init {
	return [self initFromFragment:nil view:nil];
}


- (instancetype)initFromFragment:(LadderFragment *)fragment view:(TraceView *)view {
	self = [super init];
	if (self) {
		layer = CALayer.new;
		layer.delegate = self;
		layer.actions = @{NSStringFromSelector(@selector(backgroundColor)):NSNull.null,
							NSStringFromSelector(@selector(borderWidth)):NSNull.null};
		layer.cornerRadius = 2;
		layer.borderColor = [NSColor colorWithCalibratedRed:0.4 green:0.6 blue:0.9 alpha:1].CGColor;
			
		stringLayer = CATextLayer.new;
		stringLayer.delegate = self;
		stringLayer.fontSize = 9.0;
		stringLayer.actions = @{NSStringFromSelector(@selector(contents)):NSNull.null,
								NSStringFromSelector(@selector(font)):NSNull.null,
								NSStringFromSelector(@selector(foregroundColor)):NSNull.null};
			
		stringLayer.contentsScale = 3.0; /// This makes text sharper even if the display is 2X (an 1X display requires 2X).
		stringLayer.alignmentMode = kCAAlignmentCenter;
		[layer addSublayer:stringLayer];
			
		_overlappingLabels = [NSMutableSet setWithObject:self];
		
		[self addObserver:self forKeyPath:observedKeyPaths.firstObject options:NSKeyValueObservingOptionNew context:fragmentScanChangedContext];
		[self addObserver:self forKeyPath:observedKeyPaths[1] options:NSKeyValueObservingOptionNew context:fragmentStringChangedContext];
		[self addObserver:self forKeyPath:observedKeyPaths.lastObject options:NSKeyValueObservingOptionNew context:fragmentOffsetChangedContext];
		
		self.fragment = fragment;
		self.view = view;
	}
	return self;
}


- (id)representedObject {
	return self.fragment;
}


- (BOOL)tracksMouse {		
	/// This label does not react when it is hovered
	return NO;
}


- (void)setFragment:(LadderFragment *)fragment {
	_fragment = fragment;
	if(fragment) {
		if([fragment isKindOfClass:Allele.class]) {
			if(fragment.additional) {
				type = additionalFragmentLabel;
			} else {
				type = alleleLabel;
			}
		} else {
			type = ladderFragmentLabel;
		}
		/// Allele names or sizes are show in bold.
		stringLayer.font = type == alleleLabel? (__bridge CFTypeRef _Nullable)([NSFont boldSystemFontOfSize:9]) :
		(__bridge CFTypeRef _Nullable)([NSFont labelFontOfSize:9]);
	}
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if(context == fragmentScanChangedContext) {
		[self setScan];
	} else if(context == fragmentStringChangedContext) {
		[self setString];
	} else if(context == fragmentOffsetChangedContext) {
		[self updateStringColor];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

/// sets/updates the string that the label shows.
- (void)setString {
	if (alleleNameTextField.delegate == self) {
		alleleNameTextField.hidden = YES;
	}
	stringLayer.string = self.fragment.string;
	
	/// We need to adapt the size of the layer to the string.
	TraceView *view = self.view;
	if(view.needsLayoutLabels || view.needsLayoutFragmentLabels) {
		/// If the label is to be repositioned, we defer the change of frame size to the `reposition` method.
		/// This is because a change in frame size now may start an unwanted animation.
		needsUpdateFrameSize = YES;
	} else {
		[self updateFrameSize];
		/// A change in frame size requires checking for collisions.
		[self.class avoidCollisionsInView:view allowAnimation:YES];
	}
}


/// Update or sets the appropriate string color, which depends on our type, or offset of our fragment
- (void)updateStringColor {
	TraceView *view = self.view;
	if(type == ladderFragmentLabel) {
		/// We denote our fragment's offset by the level of red in the string
		/// I haven't found a function that blends CGColorRef colors. Converting to NSColor would be simpler but probably less efficient.
		CGColorRef stringColor =  view.fragmentLabelStringColor;
		CGColorSpaceRef space = CGColorGetColorSpace(stringColor);
		if(CGColorSpaceGetModel(space) == kCGColorSpaceModelRGB) {
			const CGFloat *components = CGColorGetComponents(stringColor);
			CGFloat redComponents[] = {1, 0, 0, 1};
			/// The fraction of red depends on the original color. It's higher when it is white.
			float fraction = components[0] > 0.9 ? fabs(self.fragment.offset)/20 : fabs(self.fragment.offset)/10;
			for (int i = 0; i < 4; i++) {
				redComponents[i] = fraction * redComponents[i] + (1 - fraction) * components[i];
			}
			stringLayer.foregroundColor = CGColorCreate(space, redComponents);
		}
	} else if(type == alleleLabel) {
		stringLayer.foregroundColor = NSColor.whiteColor.CGColor;
	} else {
		stringLayer.foregroundColor = view.fragmentLabelStringColor;
	}
}


/// Update our position and color according to the scan of our fragment
- (void)setScan {
	TraceView *view = self.view;
	if(view) {
		if(!view.needsLayoutLabels && ! view.needsLayoutFragmentLabels) {
			/// a change in scan means that we must be repositioned. To make sure that collisions are avoided, we call the repositioning of all labels
			view.needsLayoutFragmentLabels = YES;
			/// we still reposition ourselves "manually", otherwise the repositioning of the label that changed peak may not be animated during undo
			[self reposition];
		}
		[self updateBackgroundColor];
	}
}


-(void) updateBackgroundColor {
	if(!self.enabled) {
		layer.backgroundColor = NSColor.darkGrayColor.CGColor;
	} else {
		TraceView *view = self.view;
		if(view) {
			if(type == alleleLabel) {
				layer.backgroundColor = view.alleleLabelBackgroundColor;
			} else if(self.fragment.scan > 0) {
				layer.backgroundColor = view.fragmentLabelBackgroundColor;
			} else {
				/// For a label that represents a ladder fragment that is unused.
				layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.5 alpha:0.7].CGColor;
			}
		}
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
	[self updateStringColor];
	[self updateBackgroundColor];
}


- (void)removeFromView {
	if(clickedTimer.isValid) {
		[clickedTimer invalidate];
	}
	_overlappingLabels = nil;
	[super removeFromView];
}


- (void)setEnabled:(BOOL)enabled {
	if(enabled != self.enabled) {
		super.enabled = enabled;
		/// we change appearance when we get enabled/disabled
		[self updateAppearance];
	}
}


- (void)updateAppearance {
	layer.borderWidth = self.highlighted?  2.0 : 0.0; /// the border becomes visible when the label is highlighted
													  /// we have a grey background when disabled
	[self updateBackgroundColor];
}



- (void)updateForTheme {
	[self updateStringColor];
	[self updateBackgroundColor];
}


# pragma mark - dragging behavior


-(void)drag {
	TraceView *view = self.view;
	NSPoint mouseLocation = view.mouseLocation;
	
	if(!self.dragged) {
		/// We do not start the drag if the user has not dragged the mouse for at least 5 points.
		/// This avoids assigning the peak to an allele for what could be a simple click
		NSPoint clickedPoint = view.clickedPoint;
		float dist = pow(pow(mouseLocation.x - clickedPoint.x, 2.0) + pow(mouseLocation.y - clickedPoint.y, 2.0), 0.5);
		if(dist < 5) {
			return;
		}
		self.dragged = YES;
	}
	
	/// The user can drag a label out (over the top edge) to remove the label.
	if(mouseLocation.y > NSMaxY(view.bounds) + 2) {
		if(!draggedOut) {
			draggedOut = YES;
			[NSCursor.disappearingItemCursor push];
		}
	} else if(draggedOut) {
		draggedOut = NO;
		[NSCursor.currentCursor pop];
	}
	
	/// We determine the peak that is the closest to the label
	float minDist = INFINITY;
	PeakLabel *closestPeak;
	for(PeakLabel *peakLabel in view.peakLabels) {
		float dist = fabs(mouseLocation.x - [view xForScan:peakLabel.scan]);
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
			layer.zPosition = 2.0;	/// a label being dragged must not be masked by another
			layer.shadowOpacity = 0.5;
			layer.shadowRadius = 5.0;
			layer.shadowOffset = CGSizeMake(0, -3);
			layer.transform = CATransform3DMakeScale(1.2, 1.2, 1);
			
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
			layer.zPosition = 0.0;
			layer.shadowOpacity = 0;
			layer.shadowRadius = 0;
			layer.transform = CATransform3DIdentity;
			if(draggedOut) {
				[self removeFragment:self];
				draggedOut = NO;
				[NSCursor.currentCursor pop];
			} else {
				[self takeDestinationPeak];
			}
			/// To avoid collision, all labels are repositioned.
			self.view.needsLayoutFragmentLabels = YES;
			[self reposition]; /// Forces the animation of the label.
		}
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
		/// if the destination is the same as the peak we already have or can't take the label (if nil for instance), we can return.
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
		allele.genotype.status = genotypeStatusManual;
		[view.undoManager setActionName:@"Edit Genotype"];
	}
}

# pragma mark - geometry

static int const topMargin = 10; /// The minimum distance between a fragment label and the top of the view

- (void)reposition {
	_yOffset = 0;
	TraceView *view = self.view;
	LadderFragment *fragment = self.fragment;
	
	if (self.hidden || view.hScale <= 0.0 || !fragment.trace || !view.trace)  {
		/// These are safety measures that may no longer be required. TO CHECK.
		return;
	}
	
	if(needsUpdateFrameSize) {
		[self updateFrameSize];
		needsUpdateFrameSize = NO;
	}
	
	NSRect viewBounds = view.bounds;
	NSRect frame = self.frame;
	
	NSPoint location;
	if(!self.dragged) {
		if(fragment.scan > 0) {
			location = [view pointForScan:fragment.scan];
			/// we position ourself a bit higher than the peak tip
			location.y += 4.0;
		} else {
			/// In this case, our fragment is "deleted"
			if(type == ladderFragmentLabel) {
				/// for a ladder fragment, we position ourselves at the top of the view and exactly at our size in base pairs
				location = NSMakePoint([view xForSize: fragment.size], NSMaxY(viewBounds) - frame.size.height);
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
			location.x = [view xForScan:destination.scan];
		}
		/// the anchor point is a the bottom of the layer (which helps positioning above peaks),
		/// but we want the label to be centered behind the cursor during drag.
		/// So we make is if the cursor location was lower by half the height of the label
		float halfHeight = frame.size.height/2;
		if(location.y < halfHeight) {
			location.y = halfHeight;
		}
		location.y -= halfHeight;
	}
	
	float margin = draggedOut? -3:topMargin;
	
	NSRect newFrame = NSMakeRect(location.x - frame.size.width/2, location.y, frame.size.width, frame.size.height);
	
	if(fragment.scan > 0 || self.dragged) {
		float delta =  NSMaxY(view.bounds) - margin - NSMaxY(newFrame); /// prevents the label from being clipped by the view
		if (delta < 0) {
			_yOffset = -delta;
			newFrame.origin.y += delta;
		}
	}
	
	self.frame = newFrame;
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


-(void)updateFrameSize {
	NSSize size = stringLayer.preferredFrameSize;
	float stringWidth = size.width;
	float width = stringWidth > 15.0 ? stringWidth : 15.0;
	NSRect bounds = NSMakeRect(0, 0, width + 2, size.height + 2);
	layer.bounds = bounds;
	_frame = layer.frame;
	stringLayer.bounds = CGRectMake(0, 0, size.width, size.height);
	stringLayer.position = CGPointMake(NSMidX(bounds), NSMidY(bounds));
}


/// Find the  `overlappingLabels` among an array of fragment labels
-(void)findOverlapsWithLabels:(NSArray *)fragmentLabels {
	if(_yOffset < -800) {
		/// We don't if we're not visible.
		_intersects = 0;
		return;
	}
	
	/// We check if any previous labels in the fragmentLabels array overlaps with us on the X axis.
	/// If any, we add all its overlappingLabels to ours. We signify this by setting us as the refLabel of each.
	/// This method called on an each member of `fragmentLabels` (in order) finds networks of labels that overlap with each others.
	_refLabel = self;
	
	for(FragmentLabel *previousLabel in fragmentLabels) {
		if(previousLabel == self) {
			break;
		}
		NSRect previousFrame = previousLabel.frame;
		if(previousLabel.yOffset > -800 && overlapXRects(previousFrame, _frame)) {
			if(previousLabel.refLabel != self) { /// Its overlapping labels have already been grabbed by us.
				NSSet *previousLabelOverlaps = previousLabel.refLabel.overlappingLabels;
				for(FragmentLabel *label in previousLabelOverlaps) {
					[label makeRefLabel:self];
					if(!_intersects) {
						_intersects = label.intersects;
					}
				}
				[_overlappingLabels unionSet: previousLabelOverlaps];
			}
			if(!_intersects) {
				_intersects = NSIntersectsRect(previousFrame, _frame);
			}
		}
	}
}


- (void)makeRefLabel:(FragmentLabel *)label {
	_refLabel = label;
}


/// Returns whether two rectangles overlap on their horizontal dimension.
/// - Parameters:
///   - rectA: A rectangle.
///   - rectB: A rectangle.
bool overlapXRects(NSRect rectA, NSRect rectB) {
	return NSMaxX(rectA) > rectB.origin.x && rectA.origin.x < NSMaxX(rectB);
}


+(void) avoidCollisionsInView:(TraceView *)view allowAnimation:(BOOL)animate {
	NSArray *fragmentLabels = view.fragmentLabels;
	if(fragmentLabels.count < 2) {
		return;
	}
	
	/// We first record overlaps on the horizontal axis.
	for(FragmentLabel *label in fragmentLabels) {
		[label findOverlapsWithLabels:fragmentLabels];
	}
	
	float ceiling = NSMaxY(view.bounds) - (view.trace.isLadder? 0 : topMargin); /// The maximum position of a top edge of a label.
	for(FragmentLabel *label in fragmentLabels) {
		NSMutableSet *overlappingLabels = label.overlappingLabels;
		NSUInteger count = overlappingLabels.count;
		if(count >= 2) {
			if(label.refLabel == label && label.intersects) {
				/// We get the label's frames and will sort them by increasing height.
				/// As we will access the overlapping labels later, we put them in an array to make sure the order is maintained.
				NSArray *overlappingLabelsArray = overlappingLabels.allObjects;
				NSRect frames[count];
				float yOrigins[count];
				vDSP_Length indices[count];
				vDSP_Length i = 0;
				for(FragmentLabel *aLabel in overlappingLabelsArray) {
					NSRect frame = aLabel.frame;
					frames[i] = frame;
					yOrigins[i] = frame.origin.y + aLabel.yOffset; /// Which corresponds to the vertical position of the label if it was not constrained by the view height.
					indices[i] = i;
					i++;
				}
				
				vDSP_vsorti(yOrigins, indices, NULL, count, 1);
				
				float maxY = 0; /// Will be the top edge position of the highest label, which we will use to determine it we must move labels down given the height of the view.
				float yOffsets[count]; /// The vertical distance by which a label will be moved
				yOffsets[0] = 0;	   /// We don't reposition the first label (bottom one).
				float lowestY = frames[indices[0]].origin.y;
				
				for (int i = 1; i < count; i++) {
					yOffsets[i] = 0;
					NSRect *frameI = &frames[indices[i]]; /// The frame that may be moved vertically to avoid a collision.
					
					/// We go through frames that are (were)  lower than `frameI` to check which overlap / intersect with it.
					long topOverlapRect = -1;  /// The indice of the highest frame that overlaps.
					float topOverlapY = 0;	   /// The top edge of its frame.
					float minOverlapY = INFINITY;  /// The bottom edge position of the lowest frame that overlaps.
					BOOL intersects = NO;		/// Whether a frame intersects with frameI.
					for (int j = 0; j < i; j++) {
						NSRect *frameJ = &frames[indices[j]];
						if(overlapXRects(*frameI, *frameJ)) {
							float y = NSMaxY(*frameJ);
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
						float originalY = frameI->origin.y;
						if((yOffsets[topOverlapRect] < 0.1)) {
							/// if the highest overlapping frame has not been moved up, we move the current frame up.
							frameI->origin.y = topOverlapY;
						} else {
							/// Otherwise, we try to move it down to avoid spreading labels too much on the vertical axis.
							/// To be safe, we try to go bellow the lowest frame that overlaps (this may not be optimal if there is room between overlapping labels
							/// on the vertical axis, but it works well enough).
							float newOrigin = minOverlapY - frameI->size.height;
							if(minOverlapY > lowestY && newOrigin > 0 && (originalY - newOrigin) < (topOverlapY - originalY)) {
								/// But we don't go this far down if the distance is greater than what were needed if we moved up.
								frameI->origin.y = newOrigin;
							} else {
								frameI->origin.y = topOverlapY;
							}
						}
						yOffsets[i] = frameI->origin.y - originalY;
					}
					float topY = NSMaxY(*frameI);
					if(maxY < topY) {
						maxY = topY;
					}
				}
				
				float excessY = maxY - ceiling;
				if(excessY > 0) {
					/// If a frame has moved too far up, we sort frames by decreasing height, as we will move them down while maintaining the relative vertical order.
					/// We don't move them all down by `excessY` as some may not need to be moved (the do only if they are "pushed" by others).
					for (vDSP_Length i = 0; i < count; i++) {
						yOrigins[i] = frames[i].origin.y;
						indices[i] = i;
					}
					vDSP_vsorti(yOrigins, indices, NULL, count, -1);
					/// We already move the top frame down as necessary
					frames[indices[0]].origin.y -= excessY;
					
					/// We check the other frames if they need to be moved down.
					for (int i = 1; i < count; i++) {
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
						float newOrigin = maxY - frame->size.height;
						if(frame->origin.y > newOrigin) {
							frame->origin.y = newOrigin;
						}
					}
				}
				
				i = 0;
				for (FragmentLabel *label in overlappingLabelsArray) {
					label.animated = animate;
					label.frame = frames[i];
					label.animated = YES;
					i++;
				}
			}
			[overlappingLabels removeAllObjects];
			[overlappingLabels addObject:label];
		}
	}
}


# pragma mark - other user actions

- (void)deleteAction:(id)sender {
	[self removeFragment:sender];
}


- (NSString *)deleteActionTitle {
	switch (type) {
		case alleleLabel:
			return @"Delete Allele";
		case additionalFragmentLabel:
			return @"Remove Peak";
		default:
			return @"Remove Ladder Size";
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
		genotype.status = genotypeStatusManual;
		if(type == additionalFragmentLabel) {
			[(Allele *)fragment removeFromGenotypeAndDelete];
		}
	}
	[undoManager setActionName: self.deleteActionTitle];
}



static NSTextField *alleleNameTextField;	/// the text field allowing the user to edit the allele name (a ladder fragment size isn't editable)
											/// we use a single instance for all labels since only one can be edited at a time

- (void)doubleClickAction:(id)sender {
	/// we show the text field allowing the user to edit an allele name directly on the trace view
	if(!self.fragment) {
		return;
	}
	
	if(type == ladderFragmentLabel) {
		[self removeFragment:sender];
		return;
	}
	
	if(!alleleNameTextField) {
		alleleNameTextField = NSTextField.new;
		alleleNameTextField.editable = YES;
		alleleNameTextField.bezeled = NO;
		alleleNameTextField.drawsBackground = YES;					/// otherwise, the label itself would show behind the text field
		alleleNameTextField.backgroundColor = NSColor.windowBackgroundColor;
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
	float newWidth = alleleNameTextField.cell.cellSize.width;
	if(newWidth < self.frame.size.width + 6) {
		newWidth = self.frame.size.width + 6;
	}
	if(newWidth > 150) {
		newWidth = 150;		/// let's stay reasonable
	}
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
			/// In this case the should not remain.
			/// The view would not do it for if the user has clicked elsewhere and the view is not the first responder.

			self.highlighted = NO;
		}
		alleleNameTextField.hidden = YES;
		NSString *actionName = type == alleleLabel? @"Rename Allele" : @"Rename Additional Peak";
		[view.undoManager setActionName:actionName];
	}
}


# pragma mark - other

- (void)dealloc {
	for(NSString *keyPath in observedKeyPaths) {
		[self removeObserver:self forKeyPath:keyPath];
	}
}

@end

