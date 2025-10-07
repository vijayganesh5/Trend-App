pipeline {
    agent any
    
    environment {
        DOCKER_IMAGE = 'vijayganesh5/trend-app'
        EKS_CLUSTER = 'trend-app-eks-cluster'
        EKS_REGION = 'ap-south-1'
    }
    
    stages {
        stage('Checkout Code') {
            steps {
                git branch: 'main', url: 'https://github.com/vijayganesh5/Trend-App.git'
            }
        }
        
        stage('Configure EKS Access') {
            steps {
                script {
                    // Update kubeconfig to access the EKS cluster
                    sh """
                        aws eks update-kubeconfig \
                          --region ${EKS_REGION} \
                          --name ${EKS_CLUSTER}
                    """
                    // Verify cluster access
                    sh 'kubectl cluster-info'
                    sh 'kubectl get nodes'
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    sh 'docker build -t ${DOCKER_IMAGE}:${BUILD_ID} .'
                }
            }
        }
        
        stage('Push to Docker Hub') {
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh '''
                            docker login -u $DOCKER_USER -p $DOCKER_PASS
                            docker push ${DOCKER_IMAGE}:${BUILD_ID}
                            docker tag ${DOCKER_IMAGE}:${BUILD_ID} ${DOCKER_IMAGE}:latest
                            docker push ${DOCKER_IMAGE}:latest
                        '''
                    }
                }
            }
        }
        
        stage('Deploy to Kubernetes') {
            steps {
                script {
                    sh 'kubectl apply -f k8s/deployment.yaml'
                    sh 'kubectl apply -f k8s/service.yaml'
                    sh 'kubectl rollout status deployment/trend-app --timeout=300s'
                    sh 'kubectl get pods -o wide'
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                script {
                    // Wait for service to get LoadBalancer
                    sh '''
                        echo "Waiting for LoadBalancer to be ready..."
                        kubectl get service trend-app-service --watch &
                        SLEEP_PID=$!
                        sleep 60
                        kill $SLEEP_PID
                    '''
                    // Get LoadBalancer URL
                    sh '''
                        echo "=== Application Details ==="
                        kubectl get deployment trend-app
                        kubectl get service trend-app-service
                        kubectl get pods -l app=trend-app
                        
                        # Get LoadBalancer URL
                        LB_URL=$(kubectl get service trend-app-service -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
                        echo "ÌæØ Application URL: http://\$LB_URL"
                    '''
                }
            }
        }
    }
    
    post {
        always {
            echo 'Pipeline execution completed'
            // Cleanup Docker images to save space
            sh 'docker system prune -f || true'
        }
        success {
            echo '‚úÖ Trend App Deployment Successful!'
            script {
                // Capture and display LoadBalancer URL
                def LB_URL = sh(
                    script: 'kubectl get service trend-app-service -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"',
                    returnStdout: true
                ).trim()
                echo "ÌæØ Your application is live at: http://${LB_URL}"
            }
        }
        failure {
            echo '‚ùå Pipeline Failed!'
            // Debug information
            sh '''
                echo "=== Debug Information ==="
                kubectl get all
                kubectl describe deployment trend-app || true
                kubectl logs -l app=trend-app --tail=50 || true
            '''
        }
    }
}
