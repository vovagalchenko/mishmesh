//
//  MMSModelPickerTableViewController.m
//  MishMeshSample
//
//  Created by Vova Galchenko on 8/26/13.
//  Copyright (c) 2013 Vova Galchenko. All rights reserved.
//

#import "MMSModelPickerTableViewController.h"
#import "MMSTableViewCell.h"
#import "MMSRemoteModelDisplayViewController.h"

#define ROOT_MMS_MODELS_KEY     @"MMSModels"
#define MODEL_NAME_KEY          @"MMSModelName"
#define NUMBER_OF_POLYGONS_KEY  @"MMSModelNumFaces"
#define URL_KEY                 @"MMSModelURL"

@interface MMSModelPickerTableViewController ()

@property (nonatomic, readwrite) NSArray *tableData;

@end

@implementation MMSModelPickerTableViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self)
    {
        self.tableData = [[NSBundle mainBundle] objectForInfoDictionaryKey:ROOT_MMS_MODELS_KEY];
    }
    return self;
}

static NSString *CellIdentifier = @"Cell";

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.tableView registerClass:[MMSTableViewCell class] forCellReuseIdentifier:CellIdentifier];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.tableData.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    NSDictionary *modelData = [self.tableData objectAtIndex:indexPath.row];
    cell.textLabel.text = [modelData objectForKey:MODEL_NAME_KEY];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ polygons", [modelData objectForKey:NUMBER_OF_POLYGONS_KEY]];
    
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    MMSRemoteModelDisplayViewController *modelDisplayVC = (MMSRemoteModelDisplayViewController *)self.presentingViewController;
    [modelDisplayVC loadFile:[NSURL URLWithString:[[self.tableData objectAtIndex:indexPath.row] objectForKey:URL_KEY]]];
    [modelDisplayVC dismissViewControllerAnimated:YES completion:nil];
}

@end