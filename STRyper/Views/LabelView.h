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
@interface LabelView : NSView <NSViewLayerContentScaleDelegate>
{
	
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
	
	/// The marker label that is hovered.
	__weak RegionLabel *hoveredMarkerLabel;
	
	/// The label that is being dragged
	ViewLabel *draggedLabel;
	
	/// Whether the mouse has entered the view and not yet exited.
	///
	/// This ivar is used internally to avoid computations that should not be performed if the mouse is not in the view.
	BOOL mouseIn;
				  
	/// A temporary context used to materialize a ``RegionLabel`` object that the user can create using the view.
	NSManagedObjectContext *temporaryContext;
	
	/// internal
	BOOL doNotCreateLabels;
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

/// Called by a label that had its ``ViewLabel/highlighted`` property changed.
///
/// The default implementation does nothing, this method is overridden.
/// - Parameter label: the label that sent this message.
-(void)labelDidChangeHighlightedState:(ViewLabel *)label;

/// Called by a label that had its ``ViewLabel/highlighted`` property changed.
///
/// - Parameter label: the label that sent this message.
-(void)labelDidChangeEnabledState:(ViewLabel *)label;

/// Called by a label that had its ``RegionLabel/editState`` property changed.
///
/// The default implementation does nothing.
/// - Parameter label: the label that sent this message.
-(void)labelDidChangeEditState:(RegionLabel *)label;


/// Called by a ``RegionLabel`` that has added a new ``Region`` (via click & drag)
/// - Parameter label: The label that added the region.
-(void)labelDidUpdateNewRegion:(RegionLabel *)label;

/// This property is used internally it to avoid doing certain calculations.
/// This pertains to internal implementation, but the markerView may query the traceView for this property.
@property (nonatomic, readonly) BOOL isMoving;

#pragma mark - labels managed by the view and represented objects

/// The ``Panel``  that the view shows.
@property (nonatomic, readonly, nullable) Panel *panel;

/// The labels for the markers that the view shows.
@property (nonatomic, readonly) NSArray<__kindof RegionLabel *> * markerLabels;

/// All the view labels that the view shows.
@property (nonatomic, readonly) NSArray<ViewLabel *> *viewLabels;

/// All view labels that may need to be repositioned in ``repositionLabels:allowAnimation:``.
///
/// ``MarkerView`` and ``TraceView`` return labels that use core animation layers.
@property (nonatomic, readonly) NSArray<ViewLabel *> *repositionableLabels;


/// Repositions labels according to the view geometry.
///
/// This method call ``ViewLabel/reposition`` on each of the `labels`.
/// - Parameters:
///   - labels: The labels to be repositioned.
///   - allowAnimate: Whether the repositioning should be animated.
- (void)repositionLabels:(NSArray *)labels allowAnimation:(BOOL) allowAnimate;


/// The label that is the target of actions in the view.
///
/// It is by default the first label among the ``viewLabels`` that is ``ViewLabel/highlighted``.
@property (nonatomic, readonly, nullable) __kindof ViewLabel *activeLabel;

/// Notifies the view that it needs to reposition its labels.
///
/// Setting this property to `YES` sets `needsLayout` to `YES`.
/// Labels are repositioned once in `-layout`.
///
/// This property is set to `YES` when the frame size of the view changes. 
@property (nonatomic) BOOL needsLayoutLabels;
															
/// Updates the tracking areas of labels.
///
/// The default implementation calls ``ViewLabel/updateTrackingArea`` on the labels.
/// - Parameter labels: The labels whose tracking areas will be updated.
- (void)updateTrackingAreasOf:(NSArray <ViewLabel *> *)labels;
	

# pragma mark -colors and appearance.

/// The default array of colors corresponding to channels (see ``Trace/channel``).
///
/// This array contains:  blue, green, dark grey, red and orange colors.
+(NSArray <NSColor *>*)defaultColorsForChannels;

/// Array of colors corresponding to channels that the view can show (see ``Trace/channel``).
///
/// If the array contains less than 5 elements or if some are not `NSColors`, the value return by ``defaultColorsForChannels`` is used.
///
/// Some colors of other elements of the view are derived from colors in this property, so using other colors than the default ones may cause visually inadequate results.
@property (nonatomic, nonnull, copy) NSArray<NSColor *>* colorsForChannels;
																
/// Whether the appearance of some of the ``viewLabels`` needs to be updated in response to change in dark/light appearance.
///
/// As some labels use core animation layers, the colors of these layers must be set during `-drawRect` or `-updateLayer` to take effect.
/// Hence setting this property to `YES` also sets `-needsDisplay` to `YES`.
///
/// Subclasses can use this property to avoid setting `CALayer` colors every time the view must redisplay.
@property (nonatomic) BOOL needsUpdateLabelAppearance;
															
/// Scrolls the view so that a label that is dragged can be moved past the left or right edge of the visible rectangle.
///
/// - Parameter draggedLabel: the label that is dragged.
- (void)autoscrollWithDraggedLabel:(ViewLabel *)draggedLabel;

/// Makes the view update the mouse cursor.
///
/// This method is called by ``labelDidChangeHoveredState:`` and ``labelEdgeDidChangeHoveredState:``.
///
/// The default implementation does nothing. Subclasses can use the ``hoveredMarkerLabel`` property and others to set the correct cursor.
- (void)updateCursor;

@end

NS_ASSUME_NONNULL_END
