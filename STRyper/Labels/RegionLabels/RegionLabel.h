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

/// A label that represents a ``Region``, either a molecular marker or a bin and allows editing its attributes.
///
/// A region label represents the range of a molecular marker (``Mmarker`` object) or a bin (``Bin``) on a ``LabelView``.
/// If shows as a rectangle taking the whole height of its host ``ViewLabel/view``.
/// It is horizontally positioned in its ``ViewLabel/view`` according to its ``start`` and ``end`` properties, but also according to its ``offset``.
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
	
	/// A rectangle representing the visible area of the label (may be different from the the value returned by ``ViewLabel/frame``)
	NSRect regionRect;
	
	/// A layer used to draw a rectangle (band) showing the range of the region.
	CALayer *bandLayer;
	
	/// The layer showing the label's name, not used by ``TraceViewMarkerLabel``.
	CATextLayer *stringLayer;
		
	/// Backs the readonly ``start`` property, and allows it to be set by subclasses.
	float _start;
	
	/// Backs the readonly ``start`` property, and allows it to be set by subclasses.
	float _end;
	
	/// Backs the readonly ``start`` property, and allows it to be set by subclasses.
	MarkerOffset _offset;
	
	/// Backs the readonly ``binLabels`` property, and allows it to be set by subclasses.
	NSArray *_binLabels;
}

/// Returns a label representing a region, added to a view.
///
/// The subclass of the label is determined by the class of the `region`, and of the `view`.
///
/// - Important: If the `view` is a ``MarkerView``, the `region` must be a ``Mmarker``.
/// This method assumes that the `region` belongs to the ``LabelView/panel`` that the `view` shows.
/// - Parameters:
///   - region: The region that the label will represent. It must be either be a ``Bin`` or a ``Mmarker`` object.
///   - view: The view on which the label will show. It must be either a ``TraceView`` or a ``MarkerView`` object.
+ (nullable __kindof RegionLabel*)regionLabelWithRegion:(Region *)region view:(__kindof LabelView *)view;


/// Returns a region label representing a new region (marker or bin) created by click & drag in a view.
///
/// Markers or bins can be created by click and drag. Which type of region is created is determined by the `view`'s class.
/// If it is a ``TraceView``, a bin will be created, otherwise a marker will be created.
/// This method uses the ``LabelView/mouseLocation`` and the ``LabelView/clickedPoint``
/// of the `view` to determine the region's start and end. These properties must be set properly before the method is called.
/// If the region could not be created, the method returns `nil` and sets the `error`.
/// - note: The method does not check if the ``Region/start`` and ``Region/end`` of the new region are valid.
/// - Important: The new region is added in a temporary managed object context on the main queue.
///
/// - Parameters:
///   - view: The view in which the label should be created.
///   - error: On output, any error preventing creating the region, which would correspond to a core data error.
+ (nullable __kindof RegionLabel*)regionLabelWithNewRegionByDraggingInView:(__kindof LabelView *)view error:(NSError * _Nullable *)error;


/// Returns a label representing a new bin created by click and drag within the receiver.
///
/// Bins can be created by click-and drag within a label representing a marker on a ``TraceView``. The receiver must be such label.
/// This method uses the ``LabelView/mouseLocation`` and the
/// ``LabelView/clickedPoint`` of the receiver's ``ViewLabel/view`` to determine the bin's start and end.
/// These properties must be set properly before the method is called. If the bin could not be created, the method returns `nil` and sets the `error`.
/// - note: The method does not check if the ``Region/start`` and ``Region/end`` of the new bin are valid.
/// - Important: The new region is added in a temporary managed object context on the main queue.
/// - Parameter error: On output, any error preventing creating the bin, which would correspond to a core data error.
- (nullable __kindof RegionLabel*)labelWithNewBinByDraggingWithError:( NSError * _Nullable *)error;

/// Whether the label represents a marker.
@property (nonatomic, readonly) BOOL isMarkerLabel;

/// Whether the label represents a bin.
@property (nonatomic, readonly) BOOL isBinLabel;


/// The region that the label represents.
///
/// ``ViewLabel/representedObject`` returns the same object.
///
/// - Important: The region must be of the class used in ``regionLabelWithRegion:view:``.
@property (nullable, nonatomic) __kindof Region *region;


/// An integer that denotes the "state" of a `RegionLabel`object.
///
/// A state determines how the label reacts to user actions, and/or the targets of these actions.
typedef NS_ENUM(NSUInteger, EditState) {
	
	/// Denotes that the label is not being used to modify any entity (other than its region).
	editStateNil = 0,
	
	/// Denotes that the label is being used to modify (move) the whole bin set of a marker.
	editStateBinSet = 1,
	
	/// Denotes that the label is being used to allow the edition of individual bins.
	editStateBins = 2,
	
	/// Denotes that the label is being used to allow editing the offset of genotypes at the marker.
	editStateOffset = 3
};


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
///
/// This property reflects the ``Region/start`` position of the ``region``.
@property (nonatomic, readonly) float start;

/// The position (in base pairs) of the right edge of the label, without considering its ``offset``.
///
/// This property reflects the ``Region/start`` position of the ``region``.
@property (nonatomic, readonly) float end;

/// The position (in base pairs) of the left edge of the label considering its ``offset``, i.e., as it appears in the ``ViewLabel/view``.
@property (nonatomic, readonly) float startSize;

/// The position (in base pairs) of the right edge of the label, considering its ``offset``, i.e., as it appears in the ``ViewLabel/view``.
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
/// The resizing/moving is only horizontal and avoid collision with other region labels (or moving outside the marker's range for a bin).
/// At the end of the drag session, the ``region``'s ``Region/start`` and ``Region/end`` attributes
/// are updated to reflect those of the label.
- (void)drag;

/// Layout the internal core animations layers of the labels.
/// The default implementation  does nothing.
/// Subclasses may perform additional modifications.
-(void)layoutInternalLayers;

/// Sets the ``RegionLabel/editState`` of the label to `editStateNil`.
- (void)cancelOperation:(id)sender;

/// The popover that is attached to the label and is shown.
@property (weak, readonly, nonatomic) NSPopover *attachedPopover;


/// For a label representing a marker on a ``TraceView``, this returns region labels for the marker's ``Mmarker/bins``.
///
/// Other types of labels return `nil`.
/// Bin labels are sorted by ascending ``RegionLabel/start``.
@property (nonatomic, nullable, readonly) NSArray<__kindof RegionLabel *> *binLabels;


/// Internal method that updates the ``Genotype/offset`` of the target genotypes to reflect the ``offset`` of the label.
///
/// Returns whether offsets were updated.
-(BOOL)_updateOffset:(MarkerOffset)offset;

/// internal method used by subclasses to update the label hovered states given the current mouse location
-(void)_updateHoveredState;

@end

NS_ASSUME_NONNULL_END
