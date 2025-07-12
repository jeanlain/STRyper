//
//  ViewLabel.h
//  STRyper
//
//  Created by Jean Peccoud on 12/01/13.
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


@import Cocoa;
@import QuartzCore;

@class TraceView;

NS_ASSUME_NONNULL_BEGIN

/// An abstract class for "labels" that show on views and represent items with which the user can interact.
///
/// A `ViewLabel` is an object that can draw itself on a ``LabelView`` and which is interactive.
/// A label represents an object that has a position or range in base pairs: a peak, a DNA fragment, a marker, a bin.
/// `ViewLabel` objects position themselves appropriately in their host view when sent a ``reposition`` message.
/// Repositioning may be required to adapt to a change in view geometry, in which case the view itself decides when to reposition
/// its labels (see ``LabelView/needsRepositionLabels`` ).
/// A `ViewLabel` may also notify the view that it needs to be repositioned, typically after an attribute of the object
/// it represents has changed.
@interface ViewLabel : NSObject <CALayerDelegate, NSMenuItemValidation>
{
	/// The base layer that can be used to display the label.
	///
	/// This variable is not set by default. Subclasses must provide their own layer.
	__kindof CALayer *layer;
	
	/// A tracking area that is used by the label to detect when the mouse enters and exits its ``frame``.
	__weak NSTrackingArea *trackingArea;
	
	/// Backs the readonly ``menu`` property and allows subclasses to set it.
	NSMenu *_menu;
	
	/// Backs the readonly ``enabled`` property and allows subclasses to set it.
	BOOL _enabled;
	
	/// Backs the readonly ``highlighted`` property and allows subclasses to set it.
	BOOL _highlighted;
	
	/// Backs the readonly ``hidden`` property and allows subclasses to set it.
	BOOL _hidden;
	
	/// Backs the readonly ``dragged`` property and allows subclasses to set it.
	BOOL _dragged;
	
	/// Backs the readonly ``hovered`` property and allows subclasses to set it.
	BOOL _hovered;
	
	BOOL _allowsAnimations;
	
	/// Backs the readonly ``frame`` property and allows subclasses to set it.
	NSRect _frame;
	
}

/// The view hosting the label.
///
/// This property is settable so that subclasses can override the setter, but one should avoid setting this property
/// and instead use the dedicated initializer of concrete subclasses.
///
/// The view class is ``TraceView`` rather than ``LabelView`` because the former has specific properties that some labels use.
/// Implementing these properties in `LabelView` doesn't seem very relevant, but it would make this property more consistent.
@property (weak, nonatomic) TraceView *view;

/// The object that the label represents.
@property (nonatomic, nullable, readonly) id representedObject;

/// The rectangle, in the view coordinate system, in which the mouse can interact with the label.
///
/// This property is not settable because a label positions itself according to other attributes, in ``reposition`` .
@property (nonatomic, readonly) NSRect frame;


#pragma mark - user interactions

/// For a label to behave properly, it should be sent the messages below when appropriate
/// These messages are sent by the hosting view to the label
///
/// Some methods are similar to those of NSResponder, but using a subclass of NSResponder would not have simplified much and may have added some overhead.
/// We don't pass NSEvents as arguments, as we don't want every label to calculate the event mouse location from the event each time.
/// The label query the -clickedPoint property of the view.


/// Sent by a ``LabelView`` to a label on `-mouseDown:`.
///
/// By default, if the label is ``enabled`` and the ``view``'s ``LabelView/clickedPoint`` lies within its ``frame``,
/// this sets the label's ``clicked`` state to `YES`, and highlights it if ``highlightedOnMouseUp`` returns `NO`.
///
/// If the clicked occurred outside the frame, this sets the ``highlighted`` property to `NO`.
- (void)mouseDownInView;

/// Sent by a ``LabelView`` to a label on `mouseDragged:`.
///
/// The default implementation calls ``drag`` on the label if it is ``clicked``.
/// - Note: This message should be received after the ``LabelView/mouseLocation`` is updated.
-(void)mouseDraggedInView;

/// Sent by a ``LabelView`` to a label on when the user has right/ctrl-clicked the view.
///
/// By default, if the label is ``enabled``  and if  ``view``-s ``LabelView/clickedPoint`` lies within its ``frame``,
/// this sets the label's ``clicked`` and ``highlighted`` states to `YES`.
- (void)rightMouseDownInView;

/// Sent by a ``LabelView`` to a label on `-mouseUp:`.
///
/// By default, if the label is ``clicked``, its ``highlighted`` state is set to `YES`  if  the ``view``-s ``LabelView/mouseUpPoint`` lies within its ``frame``.
- (void)mouseUpInView;

/// Called when the mouse enters a tracking area that the label owns.
///
/// By default this sets the label's ``hovered`` property to `YES`.
/// One should not need to call this method directly, but subclass can override it.
- (void)mouseEntered:(NSEvent *)theEvent;
										
/// Called when the mouse exits a tracking area that the label owns.
///
/// By default, this sets the label's ``hovered`` property to `NO`.
/// One should not need to call this method directly, but subclass can override it.
- (void)mouseExited:(NSEvent *)theEvent;

/// Makes the label update its tacking area(s).
///
/// The default implementation remove the label's ``trackingArea``, if existing.
/// If ``tracksMouse`` returns `YES`, adds the tracking area returned by ``addTrackingAreaForRect:`` to the ``view``.
///
/// The label calls this method when it becomes ``enabled``, but does not call it in ``reposition``
/// for performance reasons. Tracking areas need not be updated at every cycle.
- (void)updateTrackingArea;

/// Returns a suitable tracking area for the label and adds it to the label's  ``view``.
///
/// The returned tracking area reacts to mouse entered and exit events and is owned by the label.
///
/// If `rect` does not intersect with the view's visible rectangle, this method doesn't add any tracking area and returns `nil`.
/// The rectangle of the returned tracking area is clipped by the ``view``'s `visibleRect`.
///
/// This method pertains to internal implementation, but subclasses may need to call it.
/// - Parameter rect: The rectangle that the tracking area should cover.
- (nullable NSTrackingArea *) addTrackingAreaForRect:(NSRect)rect;

/// Makes the label remove its tracking area.
///
/// The default implementation removes the label's ``trackingArea`` from its ``view``.
/// Subclass can override this method (and call super) to remove additional tracking areas/rectangles or perform any relevant operation.
-(void)removeTrackingArea;

/// Whether the label is hovered.
///
/// This state can signify the user that the label is clickable, or it can be used to present some information (for instance, a tooltip).
///
/// If this property changes, the label sends ``LabelView/labelDidChangeHoveredState:`` to its ``view``.
@property (nonatomic) BOOL hovered;
						
/// Whether the label has been clicked and the mouse button is still down.
///
/// By default, a view label set ``allowsAnimations`` to `NO` when  it is clicked.
@property (nonatomic) BOOL clicked;

/// Whether the label is highlighted.
///
/// This state may be used to signify the user that an action is possible on the label.
///
/// A label gets highlighted when clicked (on `mouseDown` or `mouseUp`, depending on ``highlightedOnMouseUp``).
/// If this property changes, the label sends ``LabelView/labelDidChangeHighlightedState:`` to its ``view``.
@property (nonatomic) BOOL highlighted;

/// Whether the label should be highlighted when clicked only after the mouse button is released.
///
/// The default value is `NO` (the label can get ``highlighted`` on `mouseDown`).
@property (nonatomic, readonly) BOOL highlightedOnMouseUp;

/// Whether the label reacts to mouse move and mouse click events (when not hidden).
///
/// When this property is set to `NO`, ``hovered``, ``clicked`` and ``highlighted`` properties are set to `NO` and the label's tracking area is removed from the ``view``.
///
/// When this property changes, the label sends ``LabelView/labelDidChangeEnabledState:`` to its ``view``.
/// The default value is `YES`.
@property (nonatomic) BOOL enabled;

/// Whether the label is hidden.
///
/// Setting this property to `YES` set the ``enabled`` property to `NO` and hides the label's ``layer``.
@property (nonatomic) BOOL hidden;

/// Whether the label reacts when the mouse enter or exists its frame..
///
/// When this returns `NO`, the label does not generate a ``trackingArea`` using ``updateTrackingArea``.
/// The default implement returns is the same value as ``enabled``. Subclasses can return `YES` to make labels become hovered.
@property (nonatomic, readonly) BOOL tracksMouse;


/// Makes the label perform its dragging behavior.
///
/// This method needs not be called directly. The label calls it on itself as appropriate when receiving ``mouseDraggedInView``.
///
/// The default implementation sends ``LabelView/labelIsDragged:`` to the view.
/// Subclasses can override this method and use the ``LabelView/mouseLocation`` and ``LabelView/clickedPoint`` properties of  the ``view``.
- (void)drag;

/// Whether the label is being dragged.
@property (nonatomic, readonly) BOOL dragged;
													
/// The menu that should display when the user right/ctrl-clicks the label.
///
/// The default value is `nil`.
@property (nonatomic, nullable) NSMenu *menu;

/// The message sent by a ``LabelView`` to its ``LabelView/activeLabel`` when the user hits the delete key.
///
/// The default implementation does nothing. Subclasses are expected to override this method.
/// - Parameter sender: The object that sent this message.
-(void)deleteAction:(id)sender;

/// The message sent by a ``LabelView`` to its ``LabelView/activeLabel`` when the user hits the escape key.
///
/// The default implementation does nothing. Subclasses are expected to override this method.
/// - Parameter sender: The object that sent this message.
-(void)cancelOperation:(id)sender;
															

/// The name of the delete action, which the view can use to populate the Edit menu (form the main app menu).
///
/// This returns nothing by default. Subclasses are expected to override this method.
/// - Parameter sender: The object that sent this message.
@property (nullable, nonatomic, readonly) NSString* deleteActionTitle;

/// The message sent by a ``LabelView`` to its ``LabelView/activeLabel`` when the user double-clicked the view.
///
/// The default implementation does nothing. Subclasses are expected to override this method.
/// - Parameter sender: The object that sent this message.
- (void)doubleClickAction:(id)sender;
															

#pragma mark - position and appearance

/// Makes the label reposition itself according to the entity that it represents.
///
/// This method is expected to be called after the ``view`` geometry changes in such a way that the label needs to be repositioned,
/// or on a label that sent ``LabelView/labelNeedsRepositioning:`` to its ``view``.
///
/// The default implementation does nothing. Subclass must override this method.
- (void)reposition;

/// Prevents the label from animating its ``layer`` when set to `NO`.
///
/// When set to `NO`, the label will not use animations (when repositioning, etc.).
/// Otherwise, the label uses its default behaviour, which relies on its ``view``'s ``LabelView/allowsAnimations`` property.
///
/// The default value is `YES`
@property (nonatomic) BOOL allowsAnimations;

/// Set to `YES` to  notify that the label needs to update its appearance.
///
/// By default, the label calls the method on itself when its ``enabled``,  ``hovered`` or ``highlighted`` state changes.
/// Setting this property has no effect on a label that doesn't have a ``layer``.
///
/// Subclasses may set this property to `YES` if a label needs to update its appearance under
/// different circumstances.
@property (nonatomic) BOOL needsUpdateAppearance;

/// Updates the label's appearance to reflect its state.
///
/// The default implementation does nothing. Subclasses must override this method to visually indicate the label state.
/// The method should generally not be called directly. Instead, one may set ``needsUpdateAppearance`` to `YES`
/// to defer the update and avoid redundant updates.
- (void)updateAppearance;

/// Makes the label set the colors used by its core animation layers.
///
/// This can be called within `-drawRect` or `-updateLayer` to adapt  the label to the appearance (dark/light) of the host view..
- (void)updateForTheme;

/// Removes the label from its ``view``.
///
/// The default implementation removes the label's ``layer`` from its `superLayer`,
/// calls ``removeTrackingArea``, then sets ``view`` to `nil`.
/// Subclass that override this method should call `super` and the end.
- (void)removeFromView;


@end

NS_ASSUME_NONNULL_END
