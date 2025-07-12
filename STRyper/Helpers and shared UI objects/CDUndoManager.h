//
//  CDUndoManager.h
//  STRyper
//
//  Created by Jean Peccoud on 10/12/2023.
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


@import CoreData;

NS_ASSUME_NONNULL_BEGIN

/// An undo manager that only sets its action name when its associated managed object context has posted changes.
///
/// This class only applies to undo managers of managed object contexts, and its purpose is be able to register "possible" action names 
/// without risking that an action shows in the Edit menu if there is nothing to undo in the context.
/// This implies that the action in question changes the managed object context.
///
/// UI objects may call ``setActionName:`` when a control might have had an action on a managed object without having to check if the action actually changed to object.
/// For instance, a text field bound to an object string attribute may have ended editing, but the string value has not changed, hence the attribute was not modified.
/// In this case, and the undo manager will not register the action set by ``setActionName:``.
/// This scheme avoids the use of ``setActionName:`` in setters of managed objects, which is not a good practice.
@interface CDUndoManager : NSUndoManager


/// The managed object context associated with the receiver.
///
/// - Important: `managedObjectContext` must be the context to which the receiver is an undo manager.
/// Hence, this property must be set after the receiver has been set as the  `undoManager` of the `managedObjectContext`.
@property (weak, nonatomic) NSManagedObjectContext *managedObjectContext;


/// Sets an possible action name for the receiver.
///
/// The method has no visible effect until the receiver is notified that its ``managedObjectContext`` has changed.
/// The last action name set by this method before this notification is the one that will be used,  regardless of when this method was called.
///
/// If the ``managedObjectContext`` is `nil`, the superclass implementation is used.
///
/// - Important: To take effet, this method must be called _before_ the managed object context associated with the receiver
/// posts a change notification resulting from the action. If should therefore be called before the action is performed.
///
/// - Parameter actionName: The name of the action.
- (void)setActionName:(NSString *)actionName;


/// Forces setting the action name of the receiver.
///
/// This can be used to name an action that does not modify the ``managedObjectContext``.
/// - Parameter actionName: The name of the action.
-(void)forceActionName:(NSString *)actionName;

@end

NS_ASSUME_NONNULL_END
