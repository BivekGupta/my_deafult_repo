#The format for datasources used in the main.tf will be something like as mentioned below

data "availability_zone" "available" {
 state = "available"
}
