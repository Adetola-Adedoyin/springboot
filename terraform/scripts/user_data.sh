#!/bin/bash
# Redirect output to log file for debugging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting user data script execution"

# Initial delay to allow system initialization
echo "Waiting for system initialization..."
sleep 30

# Update system packages
echo "Updating system packages"
apt-get update -y
apt-get upgrade -y

# Install Git
echo "Installing Git"
apt-get install -y git

# Install Docker
echo "Installing Docker"
apt-get install -y docker.io
systemctl start docker
systemctl enable docker

# Add ubuntu user to docker group
echo "Adding ubuntu user to docker group"
usermod -a -G docker ubuntu

# Install Java 17
echo "Installing Java 17"
apt-get install -y openjdk-17-jdk

# Install Maven
echo "Installing Maven"
apt-get install -y maven

# Install AWS CLI v2
echo "Installing AWS CLI v2"
apt-get install -y unzip curl
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Create application directory
echo "Creating application directory"
mkdir -p /opt/app
chown ubuntu:ubuntu /opt/app

# Install Jenkins
echo "Installing Jenkins"
# Create keyrings directory if it doesn't exist
mkdir -p /etc/apt/keyrings

# Download Jenkins GPG key
wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

# Add Jenkins APT repository
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | \
  tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Configure Jenkins to use port 8090 instead of 8080
mkdir -p /etc/default
echo 'JENKINS_PORT=8090' > /etc/default/jenkins

# Update APT and install Jenkins
apt-get update -y
apt-get install -y jenkins

# CRITICAL FIX: Wait for Docker daemon to be fully ready
echo "Waiting for Docker daemon to be fully ready"
sleep 15
until docker info >/dev/null 2>&1; do
    echo "Docker daemon not ready yet, waiting 5 more seconds..."
    sleep 5
done
echo "Docker daemon is ready"

# Additional wait and ensure docker socket has correct permissions
sleep 5
chmod 666 /var/run/docker.sock

# Pull and run your Spring Boot Docker image from Docker Hub
echo "Pulling and running Spring Boot Docker image"
docker stop springboot-app 2>/dev/null || echo "No existing container to stop"
docker rm springboot-app 2>/dev/null || echo "No existing container to remove"

# Pull image with retry logic
echo "Pulling Docker image..."
for i in {1..3}; do
    if docker pull teeboss/springboot-demo:new; then
        echo "Successfully pulled Docker image"
        break
    else
        echo "Pull attempt $i failed, retrying in 10 seconds..."
        sleep 10
    fi
done

# Run container with better error handling
echo "Starting Docker container..."
if docker run -d -p 8080:8080 --name springboot-app --restart unless-stopped teeboss/springboot-demo:new; then
    echo "Container started successfully"
else
    echo "Failed to start container, checking Docker status..."
    systemctl status docker
    docker info
    exit 1
fi

# Make sure Jenkins service is started
echo "Starting Jenkins service"
systemctl start jenkins
systemctl enable jenkins

# Verify Docker container is running
echo "Verifying Docker container is running"
docker ps
docker ps -a  # Show all containers including stopped ones

# Wait for Spring Boot app to start
echo "Waiting for Spring Boot app to start"
sleep 30

# Test Spring Boot app with multiple attempts
echo "Testing Spring Boot app"
for i in {1..6}; do
    if curl -f http://localhost:8080/actuator 2>/dev/null; then
        echo "Spring Boot app is responding!"
        break
    else
        echo "Attempt $i: Spring Boot app not responding yet, waiting 10 seconds..."
        sleep 10
    fi
done

# Check Docker logs if container exists
if docker ps -q -f name=springboot-app >/dev/null; then
    echo "Container is running. Recent logs:"
    docker logs --tail 10 springboot-app
else
    echo "Container is not running. All logs:"
    docker logs springboot-app 2>/dev/null || echo "No logs available"
fi

echo "User data script completed"