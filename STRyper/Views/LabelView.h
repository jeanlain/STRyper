//
//  LabelView.h
//  STRyper
//
//  Created by Jean Peccoud on 09/08/2022.
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




#import "RegionLabel.h"
#import "NSArray+NSArrayAdditions.h"
#import "CALayer+CALayerAdditions.h"
#import "GeneratedAssetSymbols.h"

@class RulerView, Panel;

NS_ASSUME_NONNULL_BEGIN

/// An abstract class for views that show  ``ViewLabel`` objects.
///
/// A ``LabelView`` implements methods for views that show molecular marker (``Mmarker`` objects) represented by ``RegionLabel`` objects, and by extension, other classes of ``ViewLabel``.
///
/// These methods allow the user to interact with view labels, reposition these labels when needed, and has properties that labels expect from their hosting view.
///
/// The horizontal dimension of a label view represents positions/sizes in base pairs.
///
/// This superclass is tailored for the ``MarkerView`` and ``TraceView`` concrete subclasses and might not be suitable for all possible subclasses showing ``ViewLabel`` objects.
/// Instances of this class disable menu items and don't react to key-pressed events while a label is being dragged
/// to avoid unwanted effect (for instance, deleting a label being dragged).
@interface LabelView : NSView <NSViewLayerContentScaleDelegate, CALayerDelegate, NSMenuItemValidation, NSToolbarItemValidation> {
	
	/// A tracking area covering the visible rectangle of the view, so it can react to mouse movement and enter/exit events.
	NSTrackingArea *trackingArea;
	
	/// Backs the ``mouseLocation`` readonly property and allows subclasses to set it.
	NSPoint _mouseLocation;
	
	/// Backs the ``clickedPoint`` readonly property and allows subclasses to set it.
	NSPoint _clickedPoint;
	
	/// Backs the ``isMoving`` readonly property and allows subclasses to set it.
	BOOL _isMoving;
	
	/// Backs the ``panel`` readonly property and allows subclasses to set it.
	Panel *_panel;
	
	/// Backs the ``hScale`` readonly property and allows subclasses to set it.
	float _hScale;
		
	/// Backs the ``sampleStartSize`` readonly property and allows subclasses to set it.
	float _sampleStartSize;
	
	/// Backs the ``colorsForChannels`` readonly property and allows subclasses to set it.
	NSArray *_colorsForChannels;
	
	
	BOOL _resizedWithAnimation;
	/// The marker label that is hovered.
	__weak RegionLabel *hoveredMarkerLabel;
	
	/// The label that is being dragged
	ViewLabel *draggedLabel;
	
	/// The labels that need to be repositioned in `-updateLayer`
	NSMutableSet *labelsToReposition;
	
	/// Whether the mouse has entered the view and not yet exited.
	///
	/// This ivar is used internally to avoid computations that should not be performed if the mouse is not in the view.
	BOOL mouseIn;

}


#pragma mark - properties accessed and messages sent by view labels

///**********************  properties accessed and messages sent by the view labels so they position themselves, or react to user actions **************

/// The point that is clicked (on mouseDown), in the view coordinate system.
@property (nonatomic, readonly) NSPoint clickedPoint;

/// The point that is ctrl- or right-clicked, in the view coordinate system.
///
/// Its coordinates become negative on -mouseUp.
@property (nonatomic, readonly) NSPoint rightClickedPoint;

/// The point where the user has released the mouse button, in the view coordinate system.
@property (nonatomic, readonly) NSPoint mouseUpPoint;

/// Location of the mouse in the view coordinate system.
///
/// The coordinates of this point should be up-to-date even during scrolling, for a view that scrolls.
@property (nonatomic, readonly) NSPoint mouseLocation;

/// The horizontal scale of the view, in points per base pair.
///
/// In subclasses, this property is ≤0 if the view hasn't finished loading the contents, denoting that its value must not be used to position elements.
@property (nonatomic, readonly) float hScale;

/// The corresponding ``Chromatogram/startSize`` property for the ``Chromatogram`` object that is shown in the view.
///
/// This properties is used to determine the x coordinate for a size of 0 base pairs,
/// given that ``Chromatogram/startSize``  is often negative.
@property (nonatomic, readonly) float sampleStartSize;


@property (nonatomic, readonly) BOOL resizedWithAnimation;

/// Returns a size in base pairs for a given position along the x axis of the view (in quartz points).
///
/// This method relies on the ivar backing ``hScale`` and ``sampleStartSize``.
/// - Parameter xPosition: The position along the x axis of the view that is converted to a size in base pairs.
-(float)sizeForX:(float)xPosition;

/// Returns the position (in quartz points) along the x axis for a given size in base pairs
///
/// This method relies on the ivar backing ``hScale`` and ``sampleStartSize``.
/// - Parameter size: The size in base pairs that is converted into a position along the x axis of the view.
-(float)xForSize:(float)size;
///*****************

#pragma mark - message sent by view labels

/// Called by a label that had its ``ViewLabel/hovered`` property changed.
///
/// The default implementation calls ``updateCursor``.
/// - Parameter label: the label that sent this message.
-(void)labelDidChangeHoveredState:(ViewLabel *)label;

/// Called by a label that had its ``RegionLabel/hoveredEdge`` property changed.
///
/// The default implementation calls ``updateCursor``.
/// - Parameter label: the label that sent this message.
-(void)labelEdgeDidChangeHoveredState:(RegionLabel *)label;

/// Notifies the view that a label had its `highlighted` property changed.
///
///	By default, a ``ViewLabel`` calls this method on its view.
/// The default implementation does nothing, this method is overridden.
/// - Parameter label: The label that had its ``ViewLabel/highlighted`` changed .
-(void)labelDidChangeHighlightedState:(ViewLabel *)label;

/// Notifies the view that a label had its `enabled` property changed.
///
///	By default, a ``ViewLabel`` calls this method on its ``ViewLabel/view``.
/// - Parameter label: The label whose ``ViewLabel/enabled`` property has changed.
-(void)labelDidChangeEnabledState:(ViewLabel *)label;

/// Notifies the view that a `RegionLabel` had its `editState` property changed.
///
///	By default, a ``RegionLabel`` calls this method on its ``ViewLabel/view``.
/// The default implementation does nothing.
/// - Parameter label: The label that had its ``RegionLabel/editState`` changed.
-(void)labelDidChangeEditState:(RegionLabel *)label;

/// Notifies the view that a `ViewLabel` is performing its drag behavior.
///
/// - Parameter label: The label that is dragged.
-(void)labelIsDragged:(ViewLabel *)label;

/// Notifies the view that a ``RegionLabel``  has added a new ``Region`` (via click & drag).
///
///	By default, a ``ViewLabel`` calls this method on its ``ViewLabel/view``.
/// - Parameter label: The label that added the region.
-(void)labelDidUpdateNewRegion:(RegionLabel *)label;


/// Notifies the view that a ``ViewLabel``  needs to be repositioned.
///
/// This method may be called by a label to defer its repositioning in its  ``ViewLabel/view``'s  `-updateLayer` method,
/// and to avoid redundant repositioning in the same cycle.
/// - Parameter viewLabel: The label that needs to be repositioned.
- (void)labelNeedsRepositioning:(ViewLabel *)viewLabel;


/// This property is used internally it to avoid doing certain calculations.
/// This pertains to internal implementation, but the markerView may query the traceView for this property.
@property (nonatomic, readonly) BOOL isMoving;

/// Whether the labels can animate their repositioning in the current cycle.
///
/// The view manages this property itself.
/// The value is set to `YES` after labels are repositioned.
@property (nonatomic) BOOL allowsAnimations;

#pragma mark - labels managed by the view and represented objects


/// Returns region labels for an array or regions, reusing existing region labels.
///
/// The method first tries to reuse region labels whose regions are comprised in `regions`.
/// If there aren't enough labels that can be reused "as is", it attributes new regions to reused labels, or creates new labels if there aren't enough labels to reuse.
///
/// New labels are instantiated with ``RegionLabel/regionLabelWithRegion:view:``, setting the receiver as the `view` argument.
///
/// This method avoids recreating a new label for each region to represent, which takes significantly longer time than reusing a label.
/// - Parameters:
///   - regions: The region that should be represented by labels.
///   - labels: Labels that can be reused.
- (NSArray<RegionLabel *> *) regionLabelsForRegions:(NSArray<Region *> *)regions
										reuseLabels:(nullable NSArray<RegionLabel *> *)labels;

/// The layer that hosts the layer of the view's ``markerLabels``.
@property (readonly, nonatomic) CALayer *backgroundLayer;

/// The ``Panel``  that the view shows.
@property (nonatomic, readonly, nullable) Panel *panel;

/// The labels for the markers that the view shows.
@property (nonatomic, readonly) NSArray<__kindof RegionLabel *> * markerLabels;

/// All the view labels that the view shows.
@property (nonatomic, readonly) NSArray<ViewLabel *> *viewLabels;


/// Repositions labels according to the view geometry.
///
/// This method call ``ViewLabel/reposition`` on each of the `labels` and is called by the view appropriately.
/// - Parameters:
///   - labels: The labels to be repositioned.
- (void)repositionLabels:(NSArray<ViewLabel *> *)labels;


/// The label that is the target of actions in the view.
///
/// It is by default the first label among the ``viewLabels`` that is ``ViewLabel/highlighted``.
@property (nonatomic, readonly, nullable) __kindof ViewLabel *activeLabel;

/// Notifies the view that it needs to reposition its labels.
///
/// Setting this property to `YES` sets `needsDisplay` to `YES`.
/// Labels are repositioned in `-updateLayer`.
@property (nonatomic) BOOL needsRepositionLabels;
															
/// Updates the tracking areas of labels.
///
/// The default implementation calls ``ViewLabel/updateTrackingArea`` on the labels.
///
/// For performance reasons, labels don't reposition their tracking areas themselves,
/// as tracking areas need not be updated at each step of an animation.
/// - Parameter labels: The labels whose tracking areas will be updated.
- (void)updateTrackingAreasOf:(NSArray <ViewLabel *> *)labels;
	

# pragma mark - colors and appearance.


/// Array of five colors corresponding to channels that the view can show (see ``FluoTrace/channel``).
///
/// If the property contains less than five `NSColor` elements, it  returns ``defaultColorsForChannels``.
/// - Important: the colors are computed with the RGB color space to adapt to the app appearance.
@property (nonatomic, copy) NSArray<NSColor *>* colorsForChannels;


/// Default array of five colors corresponding to channels that the view can show (see ``FluoTrace/channel``).
@property (class, readonly, nonatomic) NSArray<NSColor *>* defaultColorsForChannels;


/// Recomputes the ``colorsForChannels-property`` using the RGB colorspace so they adapt to the current app appearance.
///
/// This method should be called after a change in application appearance,
/// but not necessarily within `-drawRect:` or `updateLayer`.
/// - Note:For the colors to adapt to the appearance, those set in ``colorsForChannels-property`` must be dynamic.
- (void)updateColorsForChannels;
																
/// Whether the appearance of some of the ``viewLabels`` needs to be updated in response to change in dark/light appearance.
///
/// As some labels use core animation layers, the colors of these layers must be set during `-drawRect` or `-updateLayer` to take effect.
/// Hence setting this property to `YES` also sets `-needsDisplay` to `YES`.
///
/// Subclasses can use this property to avoid setting `CALayer` colors every time the view must redisplay.
@property (nonatomic) BOOL needsUpdateLabelAppearance;
															

/// Makes the view update the mouse cursor.
///
/// This method is called by ``labelDidChangeHoveredState:`` and ``labelEdgeDidChangeHoveredState:``.
///
/// The default implementation does nothing. Subclasses can use the ``hoveredMarkerLabel`` property and others to set the correct cursor.
- (void)updateCursor;


/// Action that can be sent by a control to delete an item (or items) represented by a label (or labels).
///
/// The default implementation does nothing, but the view does perform validation
/// on a menu item that has this action.
/// - Parameter sender: The object that sent the message.
- (IBAction)deleteSelection:(id)sender;

@end

NS_ASSUME_NONNULL_END
