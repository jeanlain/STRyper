//
//  RegionLabel.h
//  STRyper
//
//  Created by Jean Peccoud on 07/03/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
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


#import "ViewLabel.h"
#import "Bin.h"
#import "Genotype.h"

@class LabelView;

NS_ASSUME_NONNULL_BEGIN

///	A label that represents a ``Region``, either a molecular marker or a bin and allows editing its attributes.
///
///	A region label represents the range of a molecular marker (``Mmarker`` object) or a bin (``Bin``) on a ``LabelView``.
///	If shows as a rectangle taking the whole height of its host ``ViewLabel/view``.
///	It is horizontally positioned in its ``ViewLabel/view`` according to its ``start`` and ``end`` properties, but also according to its ``offset``.
///
/// The ``RegionLabel`` class is the superclass of three concrete subclasses composing a "class cluster": ``MarkerLabel``, ``BinLabel`` and ``TraceViewMarkerLabel``.
/// These classes are not private, this design pattern only signifies that the ``RegionLabel`` class may not be adequate to design any subclass.
///
/// The subclasses can perform various actions on their represented ``region`` and on other objects depending on their ``editState`` property.
/// See their respective header for more information.
@interface RegionLabel : ViewLabel <NSPopoverDelegate, NSControlTextEditingDelegate, NSTextFieldDelegate>
{
	
	/// Used to determine the limit up to which a label edge can move when it is dragged and avoid on-the-fly computation
    float leftLimit, rightLimit;
		
	/// The tacking area corresponding to the left edge of the label.
	__weak NSTrackingArea *leftEdgeArea;
	
	/// The tacking area corresponding to the right edge of the label.
	__weak NSTrackingArea *rightEdgeArea;				
	
	/// The rectangle used by the tracking area covering the label edge.
	NSRect leftEdgeRect, rightEdgeRect;
	
	/// A rectangle representing the visible area of the label (may be different from the the value returned by ``ViewLabel/frame``)
	NSRect regionRect;
	
	/// A layer used to draw a rectangle (band) showing the range of the region.
	CALayer *bandLayer;
	
	/// The layer showing the label's name, not used by ``TraceViewMarkerLabel``.
	CATextLayer *stringLayer;
	
	/// The position in base pairs of the clicked point in the view, which is recorded to avoid recomputing it during a ``ViewLabel/drag``.
	float clickedPosition;
	
	/// Backs the readonly ``start`` property, and allows it to be set by subclasses.
	float _start;
	
	/// Backs the readonly ``start`` property, and allows it to be set by subclasses.
	float _end;
	
	/// Backs the readonly ``start`` property, and allows it to be set by subclasses.
	MarkerOffset _offset;
	
	/// Backs the readonly ``binLabels`` property, and allows it to be set by subclasses.
	NSArray *_binLabels;
	
}

/// Returns a label representing a region.
///
/// This methods sets the appropriate attributes for the returned label, given the `region` that it represents.
///
/// The subclass of the label is determined by the class of the `region`, and of the `view`.
///
/// IMPORTANT: if the view is a ``MarkerView``, the region must not be a ``Bin``.
///
/// This method does not check if the `region` belongs to the ``LabelView/panel`` that the `view` shows.
/// - Parameters:
///   - region: The region that the label will represent. It must be either be a ``Bin`` or a ``Mmarker`` object.
///   - view: The view on which the label will show. It must be either a ``TraceView`` or a ``MarkerView`` object.
+ (nullable __kindof RegionLabel*)regionLabelWithRegion:(Region *)region view:(__kindof LabelView *)view;

/// Whether the label represents a marker.
@property (nonatomic, readonly) BOOL isMarkerLabel;

/// Whether the label represents a bin.
@property (nonatomic, readonly) BOOL isBinLabel;


/// The region that the label represents.
///
/// ``ViewLabel/representedObject`` returns the same object.
///
/// IMPORTANT: one must not set a region of a different class from the one used in ``regionLabelWithRegion:view:``.
@property (weak, nonatomic) __kindof Region *region;


/// An integer that denotes the "state" of a `RegionLabel`object.
///
/// A state determines how the label reacts to user actions, and/or the targets of these actions.
typedef enum EditState : NSUInteger {
	
	/// Denotes that the label is not being used to modify any entity (other than its region).
	editStateNil = 0,
	
	/// Denotes that the label is being used to modify (move) the whole bin set of a marker.
	editStateBinSet,
	
	/// Denotes that the label is being used to allow the edition of individual bins.
	editStateBins,

	/// the tags below pertain to actions that change the offset of genotypes and allow to record which samples are affected
	
	/// Denotes that an action on the label will affect samples shown by its view.
	editStateOffset
} EditState;


/// The state of the label (and, depending on its value, the objects that will be affected by an action on the label).
///
/// The edit state is irrelevant and ignored for a label that represents a bin.
@property (nonatomic) EditState editState;


/// The marker offset that the label uses.
///
/// This property should reflect the ``Genotype/offset`` of the sample(s) that the ``ViewLabel/view``  shows.
///
/// The default value is `MarkerOffsetNone`.
@property (nonatomic) MarkerOffset offset;

/// The position (in base pairs) of the left edge of the label, without considering its ``offset``.
@property (nonatomic, readonly) float start;

/// The position (in base pairs) of the right edge of the label, without considering its ``offset``.
@property (nonatomic, readonly) float end;

/// The position (in base pairs) of the left edge of the label considering its ``offset``.
@property (nonatomic, readonly) float startSize;

/// The position (in base pairs) of the right edge of the label, considering its ``offset``.
@property (nonatomic, readonly) float endSize;
																
/// The edge of the label that is clicked (the mouse button still being pressed).
///
/// The returned value is `noEdge` if no edge is clicked.
///
/// This property is not readonly because it is set by the ``ViewLabel/view`` when a region is added by click & drag,
/// but setting it does not change the appearance of the label.
@property (nonatomic) RegionEdge clickedEdge;

/// Whether one of the label edges is hovered by the mouse.
@property (nonatomic, readonly) BOOL hoveredEdge;

/// Spawns a popover allowing the user to edit the name, start and end of the label's ``region``.
///
/// ``TraceViewMarkerLabel`` does not implement this method. Other subclasses call this method in ``ViewLabel/doubleClickAction:``.
/// - Parameter sender: The object that sent this message. This argument is ignored by the method.
- (void)spawnRegionPopover:(id)sender;

/// Implements the ``ViewLabel/drag`` method.
///
/// The method resizes the label if an edge has been clicked.
/// If the clicked occurred between edges and the label represents a bin, the method move the whole label.
///
///	The resizing/moving is only horizontal and avoid collision with other region labels (or moving outside the marker's range for a bin).
/// At the end of the drag session, the ``region``'s ``Region/start`` and ``Region/end`` attributes
/// are updated to reflect those of the label.
- (void)drag;

/// Sets the ``RegionLabel/editState`` of the label to `editStateNil`.
- (void)cancelOperation:(id)sender;

/// The popover that is attached to the label and is shown.
@property (weak, readonly) NSPopover *attachedPopover;


/// For a label representing a marker on a ``TraceView``, this returns region labels for the marker's ``Mmarker/bins``.
///
/// Other types of labels return `nil`.
/// Bin labels are sorted by ascending ``RegionLabel/start``.
@property (nonatomic, nullable, readonly) NSArray <__kindof RegionLabel *> *binLabels;

/// Return a label representing a bin, and adds it to the  receiver's ``binLabels`` array.
///
/// If the receiver does not represent a marker on a ``TraceView``, the method returns `nil`.
/// The method does not check if a bin already has a label or if it belongs to the ``Bin/marker`` that the receiver represents.
/// - Parameter bin: The bin that should be represented by the label.
-(nullable RegionLabel *)addLabelForBin:(Bin *)bin;

/// Internal method that updates the ``Genotype/offset`` of the target genotypes to reflect the ``offset`` of the label.
-(void)_updateOffset:(MarkerOffset)offset;

/// internal method used by subclasses to update the label hovered states given the current mouse location
-(void)_updateHoveredState;

@end

NS_ASSUME_NONNULL_END
