// Copyright (c) 2009 Imageshack Corp.
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. The name of the author may not be used to endorse or promote products
//    derived from this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
// IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
// NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
// THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// 

#import "TwitEditorController.h"
#import "LoginController.h"
#import "MGTwitterEngine.h"
#import "TweetterAppDelegate.h"
#import "LocationManager.h"
#include "util.h"
#import "TweetQueue.h"

#define SEND_SEGMENT_CNTRL_WIDTH			130
#define FIRST_SEND_SEGMENT_WIDTH			 66

#define IMAGES_SEGMENT_CONTROLLER_TAG		487
#define SEND_TWIT_SEGMENT_CONTROLLER_TAG	 42

#define PROGRESS_ACTION_SHEET_TAG										214
#define PHOTO_Q_SHEET_TAG												436
#define PROCESSING_PHOTO_SHEET_TAG										3

#define PHOTO_ENABLE_SERVICES_ALERT_TAG									666
#define PHOTO_DO_CANCEL_ALERT_TAG										13

#define K_UI_TYPE_MOVIE													@"public.movie"
#define K_UI_TYPE_IMAGE													@"public.image"

@implementation ImagePickerController

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:NO];
	[twitEditor startUploadingOfPickedMediaIfNeed];
}

@end

@implementation TwitEditorController

@synthesize progressSheet;
@synthesize currentMediaYFrogURL;
@synthesize connectionDelegate;
@synthesize _message;
@synthesize pickedMovie;
@synthesize pickedImage;

- (void)setCharsCount
{
	charsCount.text = [NSString stringWithFormat:@"%d", MAX_SYMBOLS_COUNT_IN_TEXT_VIEW - [messageText.text length]];

}

- (void) setNavigatorButtons
{
	if(self.navigationItem.leftBarButtonItem != cancelButton)
	{
		[[self navigationItem] setLeftBarButtonItem:cancelButton animated:YES];
		if([self.navigationController.viewControllers count] == 1)
			cancelButton.title = NSLocalizedString(@"Clear", @"");
		else
			cancelButton.title = NSLocalizedString(@"Cancel", @"");
	}	
		
	if([self mediaIsPicked] || [[messageText.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length])
	{
		if(self.navigationItem.rightBarButtonItem != segmentBarItem)
			self.navigationItem.rightBarButtonItem = segmentBarItem;
		
	}
	else
	{
		if(self.navigationItem.rightBarButtonItem)
			[[self navigationItem] setRightBarButtonItem:nil animated:YES];
	}

}

- (void)setMessageTextText:(NSString*)newText
{
	messageText.text = newText;
	[self setCharsCount];
	[self setNavigatorButtons];
}


- (void) setURLPlaceholder
{
	NSRange urlPlaceHolderRange = [messageText.text rangeOfString:urlPlaceholderMask];
	if([self mediaIsPicked])
	{
		if(urlPlaceHolderRange.location == NSNotFound)
		{
			NSString *newText = messageText.text;
			if(![newText hasSuffix:@"\n"])
				newText = [newText stringByAppendingString:@"\n"];
			[self setMessageTextText:[newText stringByAppendingString:urlPlaceholderMask]];
		}
	}
	else
	{
		if(urlPlaceHolderRange.location != NSNotFound)
			[self setMessageTextText:[messageText.text stringByReplacingCharactersInRange:urlPlaceHolderRange withString:@""]];
	}
}

- (void)initData
{
	_twitter = [[MGTwitterEngine alloc] initWithDelegate:self];
	inTextEditingMode = NO;
	suspendedOperation = noTEOperations;
	urlPlaceholderMask = [NSLocalizedString(@"YFrog image URL placeholder", @"") retain];
	messageTextWillIgnoreNextViewAppearing = NO;
	twitWasChangedManually = NO;
	_queueIndex = -1;
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setQueueTitle) name:@"QueueChanged" object:nil];
}

- (id)initWithNibName:(NSString *)nibName bundle:(NSBundle *)nibBundle
{
	self = [super initWithNibName:nibName bundle:nibBundle];
	if(self)
		[self initData];

	return self;
}

- (id)init
{
	return [self initWithNibName:@"PostImage" bundle:nil];
}

-(void)dismissProgressSheetIfExist
{
	if(self.progressSheet)
	{
		[self.progressSheet dismissWithClickedButtonIndex:0 animated:YES];
		self.progressSheet = nil;
	}
}

- (void)dealloc 
{
	while (_indicatorCount) 
		[self releaseActivityIndicator];

	[_twitter closeAllConnections];
	[_twitter removeDelegate];
	[_twitter release];

	[_indicator release];

	[defaultTintColor release];
	[segmentBarItem release];
	[urlPlaceholderMask release];
	self.currentMediaYFrogURL = nil;
	self.connectionDelegate = nil;
	self._message = nil;
	self.pickedImage = nil;
	self.pickedMovie = nil;
	[self dismissProgressSheetIfExist];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)setQueueTitle
{
	int count = [[TweetQueue sharedQueue] count];
	NSString *title = nil;
	if(count)
		title = [NSString stringWithFormat:NSLocalizedString(@"QueueButtonTitleFormat", @""), count];
	else
		title = NSLocalizedString(@"EmptyQueueButtonTitleFormat", @"");
	if(![[postImageSegmentedControl titleForSegmentAtIndex:0] isEqualToString:title])
		[postImageSegmentedControl setTitle:title forSegmentAtIndex:0];
}

- (void)setImageImage:(UIImage*)newImage
{
	image.image = newImage;
	[self setURLPlaceholder];
	[self setNavigatorButtons];
}


- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
	messageTextWillIgnoreNextViewAppearing = YES;
	[[picker parentViewController] dismissModalViewControllerAnimated:YES];
	[messageText becomeFirstResponder];
	[self setNavigatorButtons];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishWithPickingPhoto:(UIImage *)img pickingMovie:(NSURL*)url
{
	[[picker parentViewController] dismissModalViewControllerAnimated:YES];
	twitWasChangedManually = YES;
	messageTextWillIgnoreNextViewAppearing = YES;

	BOOL startNewUpload = NO;

	if(pickedImage != img || pickedMovie != url)
	{
		startNewUpload = YES;
		UIImage* prevImage = nil;
		if(img)
			prevImage = img;
		else if(url)
			prevImage = [UIImage imageNamed:@"MovieIcon.tif"];
		[self setImageImage:prevImage];
		self.pickedImage = img;
		self.pickedMovie = url;
	}
			
	[self setNavigatorButtons];

	if(startNewUpload)
	{
		if(self.connectionDelegate)
			[self.connectionDelegate cancel];
		self.connectionDelegate = nil;
		self.currentMediaYFrogURL = nil;
	}

	[messageText becomeFirstResponder];
	
	if(img)
	{
		BOOL needToResize;
		BOOL needToRotate;
		isImageNeedToConvert(img, &needToResize, &needToRotate);
		if(needToResize || needToRotate)
		{
			self.progressSheet = ShowActionSheet(NSLocalizedString(@"Processing image...", @""), self, nil, self.tabBarController.view);
			self.progressSheet.tag = PROCESSING_PHOTO_SHEET_TAG;
		}
	}
}



/*
- (void)imagePickerController:(UIImagePickerController *)picker didFinishWithPickingPhoto:(UIImage *)img pickingMovie:(NSURL*)url
{
	[[picker parentViewController] dismissModalViewControllerAnimated:YES];
	twitWasChangedManually = YES;
	messageTextWillIgnoreNextViewAppearing = YES;

	BOOL startNewUpload = img != image.image;

	if(!img && url)
		[self setImageImage:img];
			
	[self setNavigatorButtons];

	if(startNewUpload)
	{
		if(self.connectionDelegate)
			[self.connectionDelegate cancel];
		self.connectionDelegate = nil;
		self.currentMediaYFrogURL = nil;
	}

	[messageText becomeFirstResponder];
	
	BOOL needToResize;
	BOOL needToRotate;
	isImageNeedToConvert(img, &needToResize, &needToRotate);
	if(needToResize || needToRotate)
	{
		self.progressSheet = ShowActionSheet(NSLocalizedString(@"Processing image...", @""), self, nil, self.tabBarController.view);
		self.progressSheet.tag = PROCESSING_PHOTO_SHEET_TAG;
	}
}
*/

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
	
	if([[info objectForKey:@"UIImagePickerControllerMediaType"] isEqualToString:K_UI_TYPE_IMAGE])
		[self imagePickerController:picker didFinishWithPickingPhoto:[info objectForKey:@"UIImagePickerControllerOriginalImage"] pickingMovie:nil];
	else if([[info objectForKey:@"UIImagePickerControllerMediaType"] isEqualToString:K_UI_TYPE_MOVIE])
		[self imagePickerController:picker didFinishWithPickingPhoto:nil pickingMovie:[info objectForKey:@"UIImagePickerControllerMediaURL"]];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingImage:(UIImage *)img editingInfo:(NSDictionary *)editInfo 
{
	[self imagePickerController:picker didFinishWithPickingPhoto:img pickingMovie:nil];
}



// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad 
{
    [super viewDidLoad];
	UIBarButtonItem *temporaryBarButtonItem = [[UIBarButtonItem alloc] init];
	temporaryBarButtonItem.title = NSLocalizedString(@"Back", @"");
	self.navigationItem.backBarButtonItem = temporaryBarButtonItem;
	[temporaryBarButtonItem release];
	
	self.navigationItem.title = NSLocalizedString(@"New Tweet", @"");

	imgPicker.delegate = self;	
	messageText.delegate = self;
	
	postImageSegmentedControl.frame = CGRectMake(0, 0, SEND_SEGMENT_CNTRL_WIDTH, 30);
	segmentBarItem = [[UIBarButtonItem alloc] initWithCustomView:postImageSegmentedControl];
	[postImageSegmentedControl setWidth:FIRST_SEND_SEGMENT_WIDTH forSegmentAtIndex:0];
	defaultTintColor = [postImageSegmentedControl.tintColor retain];	// keep track of this for later
	
	[self setURLPlaceholder];
	
	BOOL cameraEnabled = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
	BOOL libraryEnabled = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary];
	if(!cameraEnabled && !libraryEnabled)
		[pickImage setHidden:YES];

	image.actualNavigationController = self.navigationController;
	[messageText becomeFirstResponder];
	inTextEditingMode = YES;
	
	_indicatorCount = 0;
	_indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
	CGRect frame = image.frame;
	CGRect indFrame = _indicator.frame;
	frame.origin.x = (int)((image.frame.size.width - indFrame.size.width) * 0.5f) + 1;
	frame.origin.y = (int)((image.frame.size.height - indFrame.size.height) * 0.5f) + 1;
	frame.size = indFrame.size;
	_indicator.frame = frame;
		
	[self setQueueTitle];
	[self setNavigatorButtons];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
	NSRange urlPlaceHolderRange = [textView.text rangeOfString:urlPlaceholderMask];
	if(urlPlaceHolderRange.location == NSNotFound && [self mediaIsPicked])
		return NO;
	
	if((urlPlaceHolderRange.location < range.location) && (urlPlaceHolderRange.location + urlPlaceHolderRange.length > range.location))
		return NO;		
	
	if(NSIntersectionRange(urlPlaceHolderRange, range).length > 0)
		return NO;		
	
	return YES;
}

- (void)textViewDidChange:(UITextView *)textView
{
	twitWasChangedManually = YES;
	[self setCharsCount];
	[self setNavigatorButtons];
}

- (void)textViewDidEndEditing:(UITextView *)textView
{
	inTextEditingMode = NO;
	[self setNavigatorButtons];
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
	inTextEditingMode = YES;
	[self setNavigatorButtons];
}

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{

}

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{

}

- (void)didReceiveMemoryWarning 
{
    [super didReceiveMemoryWarning]; // Releases the view if it doesn't have a superview
    // Release anything that's not essential, such as cached data
}


- (IBAction)finishEditAction
{
	[messageText resignFirstResponder];
}

- (NSArray*)availableMediaTypes:(UIImagePickerControllerSourceType) pickerSourceType
{
	SEL selector = @selector(availableMediaTypesForSourceType:);
	NSMethodSignature *sig = [[UIImagePickerController class] methodSignatureForSelector:selector];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
	[invocation setTarget:[UIImagePickerController class]];
	[invocation setSelector:selector];
	[invocation setArgument:&pickerSourceType atIndex:2];
	[invocation invoke];
	NSArray *mediaTypes = nil;
	[invocation getReturnValue:&mediaTypes];
	return mediaTypes;
}

- (void)grabImage 
{
	BOOL imageAlreadyExists = [self mediaIsPicked];
	BOOL photoCameraEnabled = NO;
	BOOL photoLibraryEnabled = NO;
	BOOL movieCameraEnabled = NO;
	BOOL movieLibraryEnabled = NO;
		
		
	NSArray *mediaTypes = nil;

	if([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary])
	{
		photoLibraryEnabled = YES;
		if ([[UIImagePickerController class] respondsToSelector:@selector(availableMediaTypesForSourceType:)]) 
		{
			mediaTypes = [self availableMediaTypes:UIImagePickerControllerSourceTypePhotoLibrary];
			movieLibraryEnabled = [mediaTypes indexOfObject:K_UI_TYPE_MOVIE] != NSNotFound;
			photoLibraryEnabled = [mediaTypes indexOfObject:K_UI_TYPE_IMAGE] != NSNotFound;
		}

	}
	if([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera])
	{
		photoCameraEnabled = YES;


		if ([[UIImagePickerController class] respondsToSelector:@selector(availableMediaTypesForSourceType:)]) 
		{
			mediaTypes = [self availableMediaTypes:UIImagePickerControllerSourceTypeCamera];
			movieCameraEnabled = [mediaTypes indexOfObject:K_UI_TYPE_MOVIE] != NSNotFound;
			photoCameraEnabled = [mediaTypes indexOfObject:K_UI_TYPE_IMAGE] != NSNotFound;
		}
	}

	NSString *buttons[5] = {0};
	int i = 0;
	
	if(photoCameraEnabled)
		buttons[i++] = NSLocalizedString(@"Use photo camera", @"");
	if(movieCameraEnabled)
		buttons[i++] = NSLocalizedString(@"Use video camera", @"");
	if(photoLibraryEnabled)
		buttons[i++] = NSLocalizedString(@"Use library", @"");
//	if(movieLibraryEnabled)
//		buttons[i++] = NSLocalizedString(@"Use video library", @"");
	if(imageAlreadyExists)
		buttons[i++] = NSLocalizedString(@"RemoveImageTitle" , @"");
	
	UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil
															 delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"") destructiveButtonTitle:nil
													otherButtonTitles:buttons[0], buttons[1], buttons[2], buttons[3], buttons[4], nil];
	actionSheet.actionSheetStyle = UIActionSheetStyleAutomatic;
	actionSheet.tag = PHOTO_Q_SHEET_TAG;
	[actionSheet showInView:self.tabBarController.view];
	[actionSheet release];
	
}

/*
- (void)grabImage 
{
	BOOL cameraEnabled = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
	BOOL libraryEnabled = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary];
	BOOL imageAlreadyExists = image.image != nil;
	NSString* firstButton = nil;
	NSString* secondButton = nil;
	NSString* thirdButton = nil;
	if(cameraEnabled && libraryEnabled)
	{
		firstButton = NSLocalizedString(@"Use camera", @"");
		secondButton = NSLocalizedString(@"Use library", @"");
		if(imageAlreadyExists)
			thirdButton = NSLocalizedString(@"RemoveImageTitle" , @"");
	}
	else if(cameraEnabled)
	{
		firstButton = NSLocalizedString(@"Use camera", @"");
		if(imageAlreadyExists)
			secondButton = NSLocalizedString(@"RemoveImageTitle" , @"");
	}
	else
	{
		firstButton = NSLocalizedString(@"Use library", @"");
		if(imageAlreadyExists)
			secondButton = NSLocalizedString(@"RemoveImageTitle" , @"");
	}
	
	UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil
															 delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"") destructiveButtonTitle:nil
													otherButtonTitles:firstButton, secondButton, thirdButton, nil];
	actionSheet.actionSheetStyle = UIActionSheetStyleAutomatic;
	actionSheet.tag = PHOTO_Q_SHEET_TAG;
	[actionSheet showInView:self.tabBarController.view];
	[actionSheet release];
	
}

*/

- (IBAction)attachImagesActions:(id)sender
{
	[self grabImage];
}

- (void)startUpload
{
	if(![self mediaIsPicked])
		return;

	ImageUploader * uploader = [[ImageUploader alloc] init];
	self.connectionDelegate = uploader;
	[self retainActivityIndicator];
	if(pickedImage)
		[uploader postImage:pickedImage delegate:self userData:pickedImage];
	else
		[uploader postMP4Data:[NSData dataWithContentsOfURL:pickedMovie] delegate:self userData:pickedMovie];
	[uploader release];
}

- (void)startUploadingOfPickedMediaIfNeed
{
	if(!self.currentMediaYFrogURL && [self mediaIsPicked] && !connectionDelegate)
		[self startUpload];
	
	if(self.progressSheet && self.progressSheet.tag == PROCESSING_PHOTO_SHEET_TAG)
	{
		[self.progressSheet dismissWithClickedButtonIndex:-1 animated:YES];
		self.progressSheet = nil;
	}		
}

/*
- (void)startUploadingOfPickedMediaIfNeed
{
	if(!self.currentMediaYFrogURL && image.image && !connectionDelegate)
	{
		ImageUploader * uploader = [[ImageUploader alloc] init];
		self.connectionDelegate = uploader;
		[self retainActivityIndicator];
		[uploader postImage:image.image delegate:self userData:image.image];
		[uploader release];
	}
	
	if(self.progressSheet && self.progressSheet.tag == PROCESSING_PHOTO_SHEET_TAG)
	{
		[self.progressSheet dismissWithClickedButtonIndex:-1 animated:YES];
		self.progressSheet = nil;
	}		
}
*/

- (void)postImageAction 
{
	if(![self mediaIsPicked] && ![[messageText.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length])
		return;

	if([messageText.text length] > MAX_SYMBOLS_COUNT_IN_TEXT_VIEW)
	{
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"You can not send message", @"") 
														message:[NSString stringWithFormat:NSLocalizedString(@"Cant to send too long message", @""), 1 + [urlPlaceholderMask length]]
													   delegate:nil cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"OK", @""), nil];
		[alert show];
		[alert release];
		return;
	}

	if(!self.currentMediaYFrogURL && [self mediaIsPicked] && !self.progressSheet)
	{
		suspendedOperation = send;
		if(!connectionDelegate)
			[self startUpload];
		self.progressSheet = ShowActionSheet(NSLocalizedString(@"Upload Image to yFrog", @""), self, NSLocalizedString(@"Cancel", @""), self.tabBarController.view);
		return;
	}
	
	suspendedOperation = noTEOperations;
	NSString* login = [MGTwitterEngine username];
	NSString* pass = [MGTwitterEngine password];
	
	if(!login || !pass)
	{
		[LoginController showModal:self.navigationController];
		return;
	}
	
	NSString *messageBody = messageText.text;
	if([self mediaIsPicked] && currentMediaYFrogURL)
		messageBody = [messageBody stringByReplacingOccurrencesOfString:urlPlaceholderMask withString:currentMediaYFrogURL];
	
	[TweetterAppDelegate increaseNetworkActivityIndicator];
	if(!self.progressSheet)
		self.progressSheet = ShowActionSheet(NSLocalizedString(@"Send twit on Twitter", @""), self, NSLocalizedString(@"Cancel", @""), self.tabBarController.view);
		
	postImageSegmentedControl.enabled = NO;

	NSString* mgTwitterConnectionID = nil;
	if(_message)
		mgTwitterConnectionID = [_twitter sendUpdate:messageBody inReplyTo:[[_message objectForKey:@"id"] intValue]];
	else if(_queueIndex >= 0)
		mgTwitterConnectionID = [_twitter sendUpdate:messageBody inReplyTo:_queuedReplyId];
	else
		mgTwitterConnectionID = [_twitter sendUpdate:messageBody];
		
	MGConnectionWrap * mgConnectionWrap = [[MGConnectionWrap alloc] initWithTwitter:_twitter connection:mgTwitterConnectionID delegate:self];
	self.connectionDelegate = mgConnectionWrap;
	[mgConnectionWrap release];
	
	if(_queueIndex >= 0)
		[[TweetQueue sharedQueue] deleteMessage:_queueIndex];

	return;
}

- (void)postImageLaterAction
{
	if(![self mediaIsPicked] && ![[messageText.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length])
		return;

	if([messageText.text length] > MAX_SYMBOLS_COUNT_IN_TEXT_VIEW)
	{
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"You can not send message", @"") 
														message:[NSString stringWithFormat:NSLocalizedString(@"Cant to send too long message", @""), 1 + [urlPlaceholderMask length]]
													   delegate:nil cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"OK", @""), nil];
		[alert show];
		[alert release];
		return;
	}

	NSString *messageBody = messageText.text;
	if([self mediaIsPicked] && currentMediaYFrogURL)
		messageBody = [messageBody stringByReplacingOccurrencesOfString:urlPlaceholderMask withString:currentMediaYFrogURL];

	BOOL added;
	if(_queueIndex >= 0)
	{
		added = [[TweetQueue sharedQueue] replaceMessage: messageBody 
											withImage: currentMediaYFrogURL ? nil : image.image 
											inReplyTo: _queuedReplyId
											atIndex:_queueIndex];
	}
	else
	{
		added = [[TweetQueue sharedQueue] addMessage: messageBody 
											withImage: currentMediaYFrogURL ? nil : image.image 
											inReplyTo: _message ? [[_message objectForKey:@"id"] intValue] : 0];
	}
	if(added)
	{
		if(connectionDelegate)
			[connectionDelegate cancel];
		[self setImageImage:nil];	
		self.pickedImage = nil;
		self.pickedMovie = nil;
		[self setMessageTextText:@""];
		[messageText becomeFirstResponder];
		inTextEditingMode = YES;
		[self setNavigatorButtons];
	}
	else
	{
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failed!", @"") 
														message:NSLocalizedString(@"Cant to send too long message", @"")
													   delegate:nil cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"OK", @""), nil];
		[alert show];
		[alert release];
	}
}

- (IBAction)insertLocationAction
{
	if(![[LocationManager locationManager] locationServicesEnabled])
	{
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Location service is not available on the device", @"") 
														message:NSLocalizedString(@"You can to enable Location Services on the device", @"")
													   delegate:nil cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"OK", @""), nil];
		[alert show];
		[alert release];
		return;
	}
	
	if(![[NSUserDefaults standardUserDefaults] boolForKey:@"UseLocations"])
	{
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Location service was turn off in settings", @"") 
														message:NSLocalizedString(@"You can to enable Location Services in the application settings", @"")
													   delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"") otherButtonTitles:NSLocalizedString(@"OK", @""), nil];
		alert.tag = PHOTO_ENABLE_SERVICES_ALERT_TAG;
		[alert show];
		[alert release];
		return;
	}
	
	if([[LocationManager locationManager] locationDenied])
	{
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Locations for this application was denied", @"") 
														message:NSLocalizedString(@"You can to enable Location Services by throw down settings", @"")
													   delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles:nil];
		[alert show];
		[alert release];
		return;
	}
	
	
	
	if(![[LocationManager locationManager] locationDefined])
	{
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Location undefined", @"") 
														message:NSLocalizedString(@"Location is still undefined", @"")
													   delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles:nil];
		[alert show];
		[alert release];
		return;
	}
	
	NSString* mapURL = [NSString stringWithFormat:NSLocalizedString(@"LocationLinkFormat", @""), [[LocationManager locationManager] mapURL]];
	NSRange selectedRange = messageText.selectedRange;
	[self setMessageTextText:[NSString stringWithFormat:@"%@\n%@", messageText.text, mapURL]];
	messageText.selectedRange = selectedRange;
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if(actionSheet.tag == PHOTO_Q_SHEET_TAG)
	{
		if(buttonIndex == actionSheet.cancelButtonIndex)
			return;
		
		if([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:NSLocalizedString(@"RemoveImageTitle", @"")])
		{
			twitWasChangedManually = YES;
			[self setImageImage:nil];
			self.pickedMovie = nil;
			self.pickedImage = nil;
			if(connectionDelegate)
				[connectionDelegate cancel];
			self.currentMediaYFrogURL = nil;
			return;
		}
		else if([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:NSLocalizedString(@"Use photo camera", @"")])
		{
			imgPicker.sourceType = UIImagePickerControllerSourceTypeCamera;
			if([imgPicker respondsToSelector:@selector(setMediaType:)])
				[imgPicker performSelector:@selector(setMediaType:) withObject:[NSArray arrayWithObject:K_UI_TYPE_IMAGE]];
			[self presentModalViewController:imgPicker animated:YES];
			return;
		}
		else if([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:NSLocalizedString(@"Use video camera", @"")])
		{
			imgPicker.sourceType = UIImagePickerControllerSourceTypeCamera;
			if([imgPicker respondsToSelector:@selector(setMediaType:)])
				[imgPicker performSelector:@selector(setMediaType:) withObject:[NSArray arrayWithObject:K_UI_TYPE_MOVIE]];
			[self presentModalViewController:imgPicker animated:YES];
			return;
		}
		else if([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:NSLocalizedString(@"Use library", @"")])
		{
			imgPicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
			if([imgPicker respondsToSelector:@selector(setMediaType:)])
				[imgPicker performSelector:@selector(setMediaType:) withObject:[self availableMediaTypes:UIImagePickerControllerSourceTypePhotoLibrary]];
			[self presentModalViewController:imgPicker animated:YES];
			return;
		}
		
	}
	else
	{
		suspendedOperation = noTEOperations;
		[self dismissProgressSheetIfExist];
		if(connectionDelegate)
			[connectionDelegate cancel];
	}
}

- (void)setRetwit:(NSString*)body whose:(NSString*)username
{
	if(username)
		[self setMessageTextText:[NSString stringWithFormat:NSLocalizedString(@"ReTwitFormat", @""), username, body]];
	else
		[self setMessageTextText:body];
}

- (void)setReplyToMessage:(NSDictionary*)message
{
	self._message = message;
	NSString *replyToUser = [[message objectForKey:@"user"] objectForKey:@"screen_name"];
	[self setMessageTextText:[NSString stringWithFormat:@"@%@ ", replyToUser]];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	if (self.navigationController.navigationBar.barStyle == UIBarStyleBlackTranslucent || self.navigationController.navigationBar.barStyle == UIBarStyleBlackOpaque) 
		postImageSegmentedControl.tintColor = [UIColor darkGrayColor];
	else
		postImageSegmentedControl.tintColor = defaultTintColor;
	if(!messageTextWillIgnoreNextViewAppearing)
	{
		[messageText becomeFirstResponder];
		inTextEditingMode = YES;
	}
	messageTextWillIgnoreNextViewAppearing = NO;
	[self setCharsCount];
	[self setNavigatorButtons];
}

- (void)popController
{
	[self setImageImage:nil];
	[self setMessageTextText:@""];
	self.pickedImage = nil;
	self.pickedMovie = nil;
	[self.navigationController popToRootViewControllerAnimated:YES];
}


- (IBAction)imagesSegmentedActions:(id)sender
{
	switch([sender selectedSegmentIndex])
	{
		case 0:
			[self grabImage];
			break;
		case 1:
			[self setImageImage:nil];
			self.pickedImage = nil;
			self.pickedMovie = nil;
			if(connectionDelegate)
				[connectionDelegate cancel];
			self.currentMediaYFrogURL = nil;
			break;
		default:
			break;
	}
}

- (IBAction)postMessageSegmentedActions:(id)sender
{
	switch([sender selectedSegmentIndex])
	{
		case 0:
			[self postImageLaterAction];
			break;
		case 1:
			[self postImageAction];
			break;
		default:
			break;
	}
}

- (void)uploadedImage:(NSString*)yFrogURL sender:(ImageUploader*)sender
{
	[self releaseActivityIndicator];
	id userData = sender.userData;
	if(([userData isKindOfClass:[UIImage class]] && userData == pickedImage)    ||
		([userData isKindOfClass:[NSURL class]] && userData == pickedMovie)	) // don't kill later connection
	{
		self.connectionDelegate = nil;
		self.currentMediaYFrogURL = yFrogURL;
	}
	else if(![self mediaIsPicked])
	{
		self.connectionDelegate = nil;
		self.currentMediaYFrogURL = nil;
		self.pickedImage = nil;
		self.pickedMovie = nil;
	}
	else // another media was picked
		return;
	
	if(suspendedOperation == send)
	{
		suspendedOperation == noTEOperations;
		if(yFrogURL)
			[self postImageAction];
		else
		{
			[self dismissProgressSheetIfExist];
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failed!", @"") message:NSLocalizedString(@"Error occure during uploading of image", @"")
														   delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles: nil];
			[alert show];	
			[alert release];
		}
	}
}

#pragma mark MGTwitterEngineDelegate methods

- (void)requestSucceeded:(NSString *)connectionIdentifier
{
	[TweetterAppDelegate decreaseNetworkActivityIndicator];
	[self dismissProgressSheetIfExist];
	[[NSNotificationCenter defaultCenter] postNotificationName: @"TwittsUpdated" object: nil];
	self.connectionDelegate = nil;
	image.image = nil;
	self.pickedImage = nil;
	self.pickedMovie = nil;
	[self setMessageTextText:@""];
	[messageText becomeFirstResponder];
	inTextEditingMode = YES;
	[self setNavigatorButtons];
	[self.navigationController popViewControllerAnimated:YES];
}


- (void)requestFailed:(NSString *)connectionIdentifier withError:(NSError *)error
{
	[TweetterAppDelegate decreaseNetworkActivityIndicator];
	[self dismissProgressSheetIfExist];
	self.connectionDelegate = nil;
	postImageSegmentedControl.enabled = YES;
	
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failed!", @"") message:[error localizedDescription]
												   delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles: nil];
	[alert show];	
	[alert release];
}

- (void)MGConnectionCanceled:(NSString *)connectionIdentifier
{
	postImageSegmentedControl.enabled = YES;
	self.connectionDelegate = nil;
	[TweetterAppDelegate decreaseNetworkActivityIndicator];
	[self dismissProgressSheetIfExist];
}

- (void)doCancel
{
	
	[self.navigationController popViewControllerAnimated:YES];
	if(connectionDelegate)
		[connectionDelegate cancel];
	[self setImageImage:nil];	
	self.pickedImage = nil;
	self.pickedMovie = nil;
	[self setMessageTextText:@""];
	[messageText resignFirstResponder];
	[self setNavigatorButtons];
}

- (IBAction)cancel
{
	if(!twitWasChangedManually || ([[messageText.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0 && ![self mediaIsPicked]))
	{
		[self doCancel];
		return;
	}
	
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"The message is not sent" message:@"Your changes will be lost"
												   delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"OK", nil];
	alert.tag = PHOTO_DO_CANCEL_ALERT_TAG;
	[alert show];
	[alert release];
		
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
	if(alertView.tag == PHOTO_DO_CANCEL_ALERT_TAG)
	{
		if(buttonIndex > 0)
			[self doCancel];
	}
	else if(alertView.tag == PHOTO_ENABLE_SERVICES_ALERT_TAG)
	{
		if(buttonIndex > 0)
		{
			[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"UseLocations"];
			[[LocationManager locationManager] startUpdates];
			[[NSNotificationCenter defaultCenter] postNotificationName: @"UpdateLocationDefaultsChanged" object: nil];
		}
	}
}


- (void)editUnsentMessage:(int)index
{
	
	NSString* text;
	NSData* imageData;
	if([[TweetQueue sharedQueue] getMessage:&text andImageData:&imageData inReplyTo:&_queuedReplyId atIndex:index])
	{
		_queueIndex = index;
		[self setMessageTextText:text];
		if(imageData)
		{
			self.pickedImage = [UIImage imageWithData:imageData];
			self.pickedMovie = nil;
			[self setImageImage:self.pickedImage];
		}
		[postImageSegmentedControl setTitle:NSLocalizedString(@"Save", @"") forSegmentAtIndex:0];
		[postImageSegmentedControl setWidth:postImageSegmentedControl.frame.size.width*0.5f
			forSegmentAtIndex:0];
	}
}

- (void)retainActivityIndicator
{
	if(++_indicatorCount == 1)
	{
		[image addSubview:_indicator];
		[_indicator startAnimating];
	}
}

- (void)releaseActivityIndicator
{
	if(_indicatorCount > 0)
	{
		[_indicator stopAnimating];
		[_indicator removeFromSuperview];
		--_indicatorCount;
	}
}

- (BOOL)mediaIsPicked
{
	return pickedImage || pickedMovie;
}

@end
