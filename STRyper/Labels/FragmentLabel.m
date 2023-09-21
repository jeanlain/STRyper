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

static void * const fragmentPropertyChangedContext = (void*)&fragmentPropertyChangedContext;


static NSTextField *alleleNameTextField;		/// the text field allowing the user to edit the allele name (a ladder fragment size isn't editable)
											/// we use a single instance for all labels since only one can be edited at a time

static NSArray *observedFragmentKeys;	/// the keys to observe from our fragment (note: I tried cocoa bindings, but had errors saying that some object could not be removed as observers...)
										///
typedef enum FragmentLabelType : NSUInteger {
	noTypeFragmentLabel,		/// the default type for a label that is not yet initialized
	ladderFragmentLabel,		/// for a label that represents a ladder fragment
	alleleLabel,				/// for a label that represents an allele
} FragmentLabelType;


@implementation FragmentLabel {
	FragmentLabelType type;			/// the type of label is not set externally, but by the designated initializer. It is merely a shortcut that tells whether the fragment the label represents is a ladder fragment or an allele.
	
	/// ivars used for dragging a ladder fragment label
	__weak PeakLabel *destination;		 	/// the peak label that is the destination of the fragment label being dragged
	int minAllowedScan;					 	/// the minimum scan number allowed for the destination (to ensure that ladder sizes remain in ascending order from left to right on the trace, or than an allele remains in a marker's range)
	int maxAllowedScan;						/// the max scan number of the destination (see above)
	NSColor *backgroundColor;		  	  	/// background color of the CA layer. For allele labels, the background color reflects the marker's channel
	CATextLayer *stringLayer;			  	/// shows the label name or size. It has to be separate from the base layer because the string is vertically centered, which isn't possible in a CATextLayer without subclassing
	float magnetX;						  	/// when dragging, magnetism will constrain a label to a position (in x the view coordinate system) that corresponds to the tip of a peak.
											/// This is this position. It is negative if the position is not constrained.
}

# pragma mark - init and attributes

+ (void)initialize {
	observedFragmentKeys = @[LadderFragmentScanKey, LadderFragmentStringKey, LadderFragmentOffsetKey];
}


- (instancetype)init {
	return [self initFromFragment:nil view:nil];
}


- (instancetype)initFromFragment:(LadderFragment *)fragment view:(TraceView *)view {
    self = [super init];
    if (self) {
		magnetX = -1;
		if(!layer) {
			layer = CALayer.new;
			layer.actions = @{NSStringFromSelector(@selector(borderWidth)):NSNull.null};
			layer.cornerRadius = 2;
			layer.borderWidth = 2.0;
			layer.borderColor = [NSColor colorWithCalibratedRed:0.4 green:0.6 blue:0.9 alpha:1].CGColor;
			stringLayer = CATextLayer.new;
			stringLayer.fontSize = 9.0;
			stringLayer.contentsScale = 2.0;
			stringLayer.allowsFontSubpixelQuantization = YES;
			stringLayer.alignmentMode = kCAAlignmentCenter;
			layer.delegate = self;
			[layer addSublayer:stringLayer];
		//	layer.zPosition = 1.0;		/// setting to > 0 make it appear above the edition text field
		}
        self.fragment = fragment;
		self.view = view;

    }
    return self;
}


- (id)representedObject {
	return self.fragment;
}


- (BOOL)tracksMouse {		/// This label does not react when it is hovered
	return NO;
}


- (void)setFragment:(LadderFragment *)fragment {
	/// We track changes in the properties of our fragment
	if(_fragment) {
		for (NSString *keypath in observedFragmentKeys) {
			[_fragment removeObserver:self forKeyPath:keypath];
		}
	}
    _fragment = fragment;
	if(fragment) {
		type = fragment.class == Allele.class ? alleleLabel : ladderFragmentLabel;
		stringLayer.font = type == ladderFragmentLabel? (__bridge CFTypeRef _Nullable)([NSFont labelFontOfSize:9]) :
		(__bridge CFTypeRef _Nullable)([NSFont boldSystemFontOfSize:9]);

		for (NSString *keypath in observedFragmentKeys) {
			[fragment addObserver:self forKeyPath:keypath options:NSKeyValueObservingOptionNew context:fragmentPropertyChangedContext];
		}
		if(type == alleleLabel && self.view) {
			backgroundColor = [self.view.colorsForChannels[self.fragment.trace.channel] colorWithAlphaComponent:0.7];
		}
		layer.backgroundColor = backgroundColor.CGColor;
		[self setScan];
		[self setString];
		[self setOffset];
	}
}
 

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == fragmentPropertyChangedContext) {
		if([keyPath isEqualToString:LadderFragmentScanKey]) {
			[self setScan];
		} else if([keyPath isEqualToString:LadderFragmentStringKey]) {
			[self setString];
		} else if([keyPath isEqualToString:LadderFragmentOffsetKey]) {
			[self setOffset];
		}
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

/// sets/updates the string that the label shows.
- (void)setString {
	if (alleleNameTextField.delegate == (id)self) {
		alleleNameTextField.hidden = YES;
	}
	stringLayer.string = self.fragment.string;
	NSSize size = stringLayer.preferredFrameSize;
	float stringWidth = size.width;
	float width = stringWidth > 15.0 ? stringWidth : 15.0;
	[self setFrameSize:NSMakeSize(width + 2, size.height + 2)];
	stringLayer.bounds = CGRectMake(0, 0, size.width, size.height);
	
	if(!NSEqualSizes(layer.bounds.size, self.frame.size)) {
		layer.bounds = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);
	}
	
	stringLayer.position = CGPointMake(NSMidX(layer.bounds), NSMidY(layer.bounds));
	/// as the size of the label may have changed, it needs to be repositioned.
	self.view.needsLayoutFragmentLabels = YES;
}


/// Update the string color given the offset of our ladder fragment
- (void)setOffset {
	NSColor *stringColor;
	
	if(type == ladderFragmentLabel) {
		stringColor = self.fragment.scan > 0? [NSColor colorWithCalibratedRed:fabs(self.fragment.offset)/10 green:0 blue:0 alpha:1] : NSColor.blackColor;
	} else {
		stringColor = NSColor.whiteColor;
	}
	
	stringLayer.foregroundColor = stringColor.CGColor;
}


/// Update our position according to the scan of our fragment
- (void)setScan {
	/// a change in scan means that we must be repositioned. To make sure that collisions are avoided, we call the repositioning of all labels
	self.view.needsLayoutFragmentLabels = YES;
	/// we still reposition ourselves "manually", otherwise the repositioning of the label that changed peak may not be animated during undo
	[self reposition];
	
	if(type == ladderFragmentLabel) {
		/// a ladder fragment label without a scan shows differently
		backgroundColor =  self.fragment.scan > 0? [NSColor colorWithCalibratedWhite:1 alpha:0.7] : [NSColor colorWithCalibratedWhite:0.5 alpha:0.7];
		[self updateAppearance];
	}
}


- (void)setView:(TraceView *)aView {
	if(self.view) {
		if(alleleNameTextField.delegate == (id)self) {
			alleleNameTextField.hidden = YES;
		}
	}
	super.view = aView;
	
	if(layer && self.view.layer) {
		[self.view.layer addSublayer:layer];
		if(type == alleleLabel && self.fragment) {
			backgroundColor = [self.view.colorsForChannels[self.fragment.trace.channel] colorWithAlphaComponent:0.7];
			layer.backgroundColor = backgroundColor.CGColor;
		}
	}
	[self updateAppearance];
}



- (void)setEnabled:(BOOL)enabled {
	if(enabled != self.enabled) {
		super.enabled = enabled;
		/// we change appearance when we get enabled/disabled
		[self updateAppearance];
	}
}


- (void)updateAppearance {
	[layer setNeedsLayout]; /// Which avoid updating our appearance too many times
}


- (void)layoutSublayersOfLayer:(CALayer *)layer {
	/// The layer doesn't have sublayer, but this method is useful to update its content, though this method is not meant for that...
	layer.borderWidth = self.highlighted?  2.0 : 0.0; /// the border becomes visible when the label is highlighted
	/// we have a grey background when disabled
	layer.backgroundColor = self.enabled? backgroundColor.CGColor : NSColor.darkGrayColor.CGColor;
}

# pragma mark - dragging behavior


-(void)drag {
	/// We do not start the drag if the user has not dragged the mouse for at least 5 points.
	/// This avoids assigning the peak to an allele for what could be a simple click
	TraceView *view = self.view;
	NSPoint clickedPoint = view.clickedPoint;
	NSPoint mouseLocation = view.mouseLocation;
	float dist = pow(pow(mouseLocation.x - clickedPoint.x, 2.0) + pow(mouseLocation.y - clickedPoint.y, 2.0), 0.5);
	if(dist < 5) {
		return;
	}

	self.dragged = YES;
	[self reposition];
	
	destination = nil;
	/// we find our possible destination (peak), as we are being dragged
	/// This is the closest peak to the mouse location (in x coordinates)
	/// The mouse location is distant to a peak tip by less than half of the label frame, the label will be constrained to the peak x position (magnetism)
	float refDist = self.frame.size.width /2;
	if(refDist > 15) {
		refDist = 15;
	}
	
	float minDist = INFINITY;	/// the closest recorded distance between a peak tip and the mouse location
	PeakLabel *closestPeak;
	float closestPeakPos = 0;
	
	for(PeakLabel *peakLabel in self.view.peakLabels) {
		peakLabel.hovered = NO;
		if (peakLabel.scan >= minAllowedScan) {
			float peakPos = [view xForScan: peakLabel.scan];
			float dist = fabs(mouseLocation.x - peakPos);
			if(dist < minDist) {
				minDist = dist;
				closestPeak = peakLabel;
				closestPeakPos = peakPos;
			} else {
				break;
				/// as peak labels come by increasing positions, we can break once the distance to the mouse starts to increase
			}
		}
	}
	
	if((minDist < refDist || NSPointInRect(mouseLocation, destination.frame)) && closestPeak.scan <= maxAllowedScan) {
		destination = closestPeak;
		destination.hovered = YES;	/// to show the candidate destination, we make it show its hovered state
		if(minDist < refDist) {
			if(magnetX != closestPeakPos) {
				/// We signify magnetism with haptic feedback
				[NSHapticFeedbackManager.defaultPerformer performFeedbackPattern:NSHapticFeedbackPatternAlignment
																 performanceTime:NSHapticFeedbackPerformanceTimeDefault];
			}
			magnetX = closestPeakPos;
		} else {
			magnetX = -1;
		}
	} else {
		magnetX = -1;
	}
}


- (void)setDragged:(BOOL)dragged {
	if(dragged != self.dragged) {
		_dragged = dragged;
		layer.zPosition = dragged? 2.0: 0.0;	/// a label being dragged must not be masked by another
		
		if(dragged) {
			/// A label cannot be dragged to any peak. We determine the min and max scans of the destination peak
			NSArray	*ladderFragments = [self.view.trace.fragments sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"size" ascending:YES]]];
			minAllowedScan = 0; maxAllowedScan = 50000;
			if(type == ladderFragmentLabel) {
				/// For a ladder fragment label The destination must ensure that ladder sizes remain in ascending order from left to right
				float size = self.fragment.size;
				for(LadderFragment *ladderFragment in ladderFragments) {
					if(ladderFragment.scan <= 0) {
						continue;
					}
					if(ladderFragment.size < size) {
						minAllowedScan = ladderFragment.scan;		/// we can take the scan from the fragment on the left or the peak
					} else if(ladderFragment.size > size) {		/// up to the scan from the fragment on the right
						maxAllowedScan = ladderFragment.scan;
						break;
					}
				}
			} else {
				/// for an allele label, the destination must be within the marker's range
				Allele *allele = (Allele *)self.fragment;
				Mmarker *marker = allele.genotype.marker;
				Chromatogram *sample = self.view.trace.chromatogram;
				if(marker && sample) {
					minAllowedScan = [sample scanForSize: marker.start];
					maxAllowedScan = [sample scanForSize: marker.end];
				}
			}
		} else {
			/// The label is no longer dragged, the user must have released the mouse.
			magnetX = -1;
			[self moveToDestination];
		}
		
		[self reposition];
	}
}


/// Moves the label to destination or back to its original position
-(void) moveToDestination {
	/// We make sure that collisions are avoided even if the label gets back to its origin peak and the its scan hasn't changed
	/// (for alleles in particular, as two labels can be positioned on the same peak).
	TraceView *view = self.view;
	LadderFragment *fragment = self.fragment;
	view.needsLayoutFragmentLabels = YES;
	
	if(!destination || destination.scan == fragment.scan) {
		/// if the destination is the same as the peak we already have, we can return
		return;
	}
	
	LadderFragment *destinationFragment = destination.fragment;
	
	if(destinationFragment && type == ladderFragmentLabel) {
		/// if the destination already has a ladder fragment, we de-assign it
		destinationFragment.scan = 0;
		destinationFragment.offset = 0.0;
		destinationFragment = nil;				///  we  also remove the fragment from the peak label
	}
	
	/// we give our fragment the scan of the destination
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
			Mmarker *marker = allele.genotype.marker;
			if(allele && marker) {
				[marker binAllele:allele];
			}
		}
		allele.genotype.status = genotypeStatusManual;
		[view.undoManager setActionName:@"Edit Genotype"];
	}
}

# pragma mark - geometry

- (void)reposition {
	TraceView *view = self.view;
	LadderFragment *fragment = self.fragment;
	
	if (self.hidden || view.hScale <= 0.0 || !fragment.trace || !view.trace)  {
		/// we may still be present after our ladder peak is removed from a trace
		return;
	}
	
	NSRect viewFrame = view.frame;
	NSRect frame = self.frame;
	
	self._distanceToMove = 0;
	NSPoint location;
	if(!self.dragged) {
		if(fragment.scan > 0) {
			location = [view pointForScan:fragment.scan];
			/// we position ourself a bit higher than the peak tip
			location.y += 4.0;
		} else {
			/// In this case, our fragment is "deleted"
			if(type == ladderFragmentLabel) {
				/// for a ladder fragment, we position ourselves at the top of the view and and exactly at our size in base pairs
				location = NSMakePoint([view xForSize: fragment.size], NSMaxY(viewFrame) - frame.size.height);
			} else {
				/// For an deleted allele, we position above our view (higher than its frame), at the midpoint of the marker range
				Mmarker *marker = ((Allele *)fragment).genotype.marker;
				float midSize = (marker.end + marker.start)/2;
				location = NSMakePoint([view xForSize:midSize], NSMaxY(viewFrame) + 20);
			}
		}
	} else {
		location = self.view.mouseLocation;
		if(magnetX >= 0) {
			location.x = magnetX;
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
	
	NSRect newFrame = NSMakeRect(location.x - frame.size.width/2, location.y, frame.size.width, frame.size.height);
	
	if(fragment.scan > 0) {
		float temp =  NSMaxY(view.bounds) - 10 - NSMaxY(newFrame); /// prevents the label from being clipped by the view
		if (temp < 0) {
			newFrame.origin.y += temp;
		}
	}
	
	if(!self.dragged) {
		_frame = newFrame;		/// we set a tentative frame (hence why we don't use the setter), as we now check for collisions
		[self avoidCollisions];
	} else {
		self.frame = newFrame;
	}
	
}


- (void)setFrame:(NSRect)rect {
	_frame = rect;
	layer.position = CGPointMake(NSMidX(rect), NSMidY(rect));
	/// if the textfield allowing to edit the name is shown, we must move it in concert.
	if(alleleNameTextField.delegate == (id)self && alleleNameTextField.superview) {
		/// we set its middle x position the same as ours
		[alleleNameTextField setFrameOrigin:NSMakePoint(rect.origin.x + rect.size.width/2 - alleleNameTextField.frame.size.width/2, rect.origin.y)];
	}

}


- (void)setFrameSize:(NSSize)newSize {
	self.frame = NSMakeRect(self.frame.origin.x, self.frame.origin.y, newSize.width, newSize.height);
}


/// Avoids collision with other ladder labels
- (void)avoidCollisions {
	NSRect ourFrame = self.frame;
    for (FragmentLabel *aLabel in self.view.fragmentLabels) {
		/// we only check for collision with fragments that have been already positioned
		/// so we can stop once we encounter ourselves
		/// IMPORTANT NOTE : this assumes that the view repositions the labels by enumerating its fragmentLabels array
		if(aLabel == self) {
			break;
		}
        NSRect aFrame = aLabel.frame;
        if (NSIntersectsRect(ourFrame, aFrame) && !aLabel.hidden) { ///we only check labels that had their frame updated
            float aLabelAmount = [aLabel distanceToMoveToAvoidOverlapWith:ourFrame];
            float ourAmount = [self distanceToMoveToAvoidOverlapWith:aFrame];;
            if (fabsf(ourAmount) < fabsf(aLabelAmount)-0.1) { 		/// we move us or the overlapping label, whichever involves the smaller offset
				ourFrame.origin.y += ourAmount;
                if (ourAmount > 0) {    //we move up
                    aLabel._distanceToMove = NSMaxY(ourFrame) - NSMinY(aFrame);
                } else {                //we move down
                    aLabel._distanceToMove = NSMinY(ourFrame) - NSMaxY(aFrame);
                }
            }
            else {
                aFrame.origin.y += aLabelAmount;
				aLabel.animated = self.animated;
                aLabel.frame = aFrame;
				aLabel.animated = YES;
                if (aLabelAmount > 0) {  /// the other label has moved up
                    self._distanceToMove = NSMaxY(aFrame) - NSMinY(ourFrame);
                } else {                /// the other label has moved down
                    self._distanceToMove = NSMinY(aFrame) - NSMaxY(ourFrame);
                }
            }
        }
    }
	
    self.frame = ourFrame;

}


- (float) distanceToMoveToAvoidOverlapWith:(NSRect)bRect {
	NSRect aRect = self.frame;
    float dist = NSMaxY(bRect) - NSMinY(aRect);      /// by default, we move the rectangle upward
	if (dist < self._distanceToMove)  {
		/// we move it as much as necessary to avoid collision with another label
		dist = self._distanceToMove;
	}
    if (NSMaxY(aRect) + dist > NSMaxY(self.view.bounds) - 10) {
		/// if the label would go out of the view bounds, we move it down
        dist = NSMinY(bRect) - NSMaxY(aRect);
		if (dist > self._distanceToMove) {
			dist = self._distanceToMove;
		}
    }
    return dist;
}

# pragma mark - other user actions

- (void)deleteAction:(id)sender {
	[self removeFragment:sender];
}


- (NSString *)deleteActionTitle {
	return type == alleleLabel? @"Delete Allele" : @"Remove Ladder Size";

}


- (void)removeFragment:(id)sender {
	LadderFragment *fragment = self.fragment;
	if(!fragment) {
		return;
	}
	fragment.scan = 0;		/// which will reposition the label
	if(type == ladderFragmentLabel) {
		/// the user wants to remove our ladder fragment from sizing
		[fragment.trace.chromatogram computeFitting];			/// we need to recompute sizing as the fragments have changed
	} else {
		Genotype *genotype = [(Allele *)fragment genotype];
		genotype.status = genotypeStatusManual;
	}
	[self.view.undoManager setActionName: self.deleteActionTitle];
}


- (void)doubleClickAction:(id)sender {
	/// we show the text field allowing the user to edit an allele name directly on the trace view
	if(!self.fragment || type == ladderFragmentLabel) {
		return;		/// irrelevant for label representing ladder fragments
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
	if(alleleNameTextField.delegate != (id)self) {
		[alleleNameTextField bind:NSValueBinding toObject:self withKeyPath:@"fragment.name" options:nil];
		[self.view addSubview:alleleNameTextField];
		alleleNameTextField.delegate = (id)self;
	}
	alleleNameTextField.hidden = NO;
	alleleNameTextField.frame = NSInsetRect(self.frame, -3, 0);
	[alleleNameTextField selectText:self];
	self.highlighted = YES; 	/// we make sure we stay highlighted (the textfield becoming the first responder would make the trace view de-highlight us)
}


- (void)cancelOperation:(id)sender {
	/// Hides the textField without applying its value to the name of our fragment
	if(!alleleNameTextField.hidden && alleleNameTextField.delegate == (id)self) {
		[alleleNameTextField unbind:NSValueBinding];
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
	[alleleNameTextField setFrame:NSMakeRect(NSMidX(rect) - newWidth/2, rect.origin.y, newWidth, rect.size.height)];
}


- (void)controlTextDidEndEditing:(NSNotification *)obj {
	if(obj.object == alleleNameTextField) {
		NSWindow *window = self.view.window;
		if(window.firstResponder == window) {
			/// when the user validates with the enter key, the first responder becomes the window, which is not desirable
			[window performSelector:@selector(makeFirstResponder:) withObject:self.view afterDelay:0.0];
		}
		alleleNameTextField.hidden = YES;
	}
}


# pragma mark - other

- (void)dealloc {
	if(_fragment) {
		for (NSString *keypath in observedFragmentKeys) {
			[_fragment removeObserver:self forKeyPath:keypath];
		}
	}
}

@end

