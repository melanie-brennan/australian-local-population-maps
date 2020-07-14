install.packages("ggplot2")
install.packages("rgdal")
install.packages("maptools")
install.packages("plyr")
install.packages("devtools")
#Note that gpclib neeeds the rtools .exe to be installed. Use devtools function find_rtools() to check rtools installation
install.packages("https://cran.r-project.org/src/contrib/gpclib_1.5-6.tar.gz", type="source", repos = NULL)
install.packages("ggsn")
install.packages("geosphere")

library(gpclib)
library(ggplot2)
library(rgdal)
library(maptools)
library(plyr)
library(devtools)
library(ggsn)
library(geosphere)

# Functions
get_census_data <- function(data_source){
  # Read in the 2016 census data - two ways to do it, "offline" or "online"
  # Arguments:
  # data_source: valid values are "offline" or "online"
  #              "offline" means that the census data has already been manually downloaded  
  #               unzipped and placed in the same folder as the main.R file.
  #               File is named "2016_census_mesh_block_counts.csv"
  #              "online:" means the map data needs to downloaded, unzipped whilst running the main.R script
  
  if (data_source == "offline") {
    #read in the existing offline data
    census <- read.csv("2016_census_mesh_block_counts.csv", stringsAsFactors = FALSE)
  }
  
  else if (data_source == "online") {
    url <- "https://www.abs.gov.au/AUSSTATS/subscriber.nsf/log?openagent&2016%20census%20mesh%20block%20counts.csv&2074.0&Data%20Cubes&1DED88080198D6C6CA2581520083D113&0&2016&04.07.2017&Latest"
    
    #download the data, unzip it
    download.file(url, destfile = "2016_census_mesh_block_counts.csv" , mode='wb')
  
    #read in the data
    census <- read.csv("2016_census_mesh_block_counts.csv", stringsAsFactors = FALSE)
  }
  
  else {
    print("Invalid census data source.")
    quit(save="ask")
  }
  
  return(census)
  
}


get_map_data <- function(data_source){
  #read in the 2016 map data - two ways to do it, "offline" or "online"
  # Arguments:
  # data_source: valid values are "existing" or "online"
  #              "offline" means that the map data has already been manually downloaded, 
  #               unzipped and placed in the same folder as the main.R file.
  #               File name is 1270055001_mb_2016_nsw_shape
  #              "online:" means the map data needs to downloaded, unzipped whilst running the main.R script
  
  if (data_source == "offline") {
    #read in the existing offline data
    nsw <- readOGR(dsn="1270055001_mb_2016_nsw_shape", layer= "MB_2016_NSW") 
  }
  
  else if (data_source == "online") {
    url <- "https://www.abs.gov.au/AUSSTATS/subscriber.nsf/log?openagent&1270055001_mb_2016_nsw_shape.zip&1270.0.55.001&Data%20Cubes&E9FA17AFA7EB9FEBCA257FED0013A5F5&0&July%202016&12.07.2016&Latest"
    
    #download the data, unzip it
    download.file(url, destfile = "1270055001_mb_2016_nsw_shape.zip" , mode='wb')
    unzip("1270055001_mb_2016_nsw_shape.zip", exdir = ".")
    file.remove("1270055001_mb_2016_nsw_shape.zip")

    #read in the data
    nsw <- readOGR(dsn="nsw_data_shape", layer= "MB_2016_NSW") 
  }
  
  else {
    print("Invalid map data source.")
    quit(save="ask")
  }
  
  return(nsw)

}


get_statistical_area <- function(map_data, statistical_area_name, census_data) {
  # Function get_statistical_area returns points and data for name found in the census data "Statistical Area 2 Name"
  # map data is spdf (Spatial Polygons Datframe), statistical_area_name is a string, census_data is a dataframe
  # Arguments:
  # map_data: map_data, in this project map data is NSW data
  # statistical_area_name: Local area name as defined by the Australian Bureau of statistics
  # census_data: in this project it is 2016 Australian Census Data

  gpclibPermit()
  
  #get the points for just the area of interest using regular expression to match the text.
  statistical_area_points <- fortify(map_data[grep(statistical_area_name, map_data$SA2_NAME16), ], region = "id")
  
  #join with other map data
  statistical_area <- join(statistical_area_points, map_data@data, by = "id")
  
  #match the mesh block ideas from map data and the census housing data
  matched_mesh_block <- match(statistical_area$MB_CODE16, census_data$MB_CODE_2016)
  
  #create columns for number of people, and dwellings for each mesh block
  statistical_area$persons <- census[matched_mesh_block, "Person"]
  statistical_area$dwellings<- census[matched_mesh_block, "Dwelling"]
  
  # calculate the number of people per dwelling for each mesh block.  If there are no dwellings make the ratio = NA
  statistical_area$personsPerDwelling <-ifelse(statistical_area$dwellings==0, NA, statistical_area$persons/statistical_area$dwellings)
  
  return(statistical_area)
}


get_scale_dist <- function(long_min, long_max, lat_min, lat_max) {
  # Gives an approximation of the scale to use.
  # 1 degree of latitude is approx 111 km.  
  # 1 degree of longitude is approx 98 km in northern NSW and 88 km in southern NSW (Calculator at johndcook.com)
  # Using average (93) km per degree of latitude and longitude
  # Arguments:
  # long_min, long_max: the smallest and largest longitude values respectively
  # lat_min, lat_max: the smallest and larget latitiude values respectively

  #find the maps dimensions in degrees
  map_width <- (long_max - long_min) * 111 
  map_height <- (lat_max - lat_min) * 93  

  #get the larger dimension
  largest_map_dim = max(map_height, map_width)
  
  #Use thresholding with the findInterval function to get the scale distance
  thresholds <- c(-Inf, 0.1, 0.5, 1.0, 5.0, 10, 50, 100, 500, 1000, Inf)
  scale_dists <- c(0.01, 0.05, 0.1, 0.5, 1 , 5, 10, 50, 100, 500)
  scale_dist <-  scale_dists[findInterval(largest_map_dim, thresholds)]
  
  return(scale_dist)
}


#Main section

#read in the 2016 census data - it can use existing data ("offline") or download from the ABS website ("online")
#"offline" as file is small and can be easily stored on in github repository
census <- get_census_data("offline")

# get the 2016 nsw map shape data - it can use existing data ("offline") or download from the ABS website ("online")
nsw <- get_map_data("online")

#set the mesh id to the row
nsw@data$id <- rownames(nsw@data)

# Get local area information, each area will be saved as a png file
local_area_names <- c("Maroubra", "Moree")

for(local_area_name in local_area_names){
  #get the data for the local area
  local_area <- get_statistical_area(nsw, local_area_name, census)

  #get the extremes of the local area's longitude and latitude
  # These values will represent the most north, east, south and west locations
  long_min <- min(local_area$long)
  long_max <- max(local_area$long)
  lat_min <-  min(local_area$lat)
  lat_max <- max(local_area$lat)
  
  #get an appropriate scale distance depending on map size
  scale_dist <- get_scale_dist(long_min, long_max, lat_min, lat_max)
  
  #create a file name and open a png file
  filename <- paste(local_area_name,".png")
  png(filename, width=720, height = 630)

  #plot the number of people per dwelling by meshblock
  plot <- ggplot(local_area) + 
        aes(long, lat, group = group, fill = personsPerDwelling) + 
        geom_polygon() + 
        coord_equal() + 
        theme_bw() + 
        geom_path(color = "ivory3") + 
        theme(axis.ticks = element_blank(), axis.text = element_blank(), axis.title = element_blank(), panel.grid = element_blank(), panel.border = element_blank(), plot.title = element_text(hjust = 0.5)) + 
        labs(title = paste("Number of people per dwelling in the",local_area_name,"area, NSW \n\n Data source: Australian Bureau of Statistics 2016 Census")) + 
        scale_fill_continuous("People per dwelling", low = "rosybrown1", high = "tomato3", na.value="white") +
        scalebar(local_area, transform = TRUE, dist = scale_dist, dist_unit ="km", model = 'WGS84', location="bottomleft")

  #display  the plot
  print(plot)
  
  #close the png file
  dev.off()
}