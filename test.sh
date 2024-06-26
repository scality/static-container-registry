# This file is to be executed using `bash_unit`

DOCKER=${DOCKER:-$(command -v docker || echo false)}
SKOPEO=${SKOPEO:-$(command -v skopeo || echo false)}
CRICTL=${CRICTL:-$(command -v crictl || echo false)}
ORAS=${ORAS:-$(command -v oras || echo false)}
CURL=${CURL:-$(command -v curl || echo false)}
HARDLINK=${HARDLINK:-$(command -v hardlink || echo false)}

IMAGE=${IMAGE-nicolast/static-container-registry:test}
IMAGES=${IMAGES-/tmp/images}
CONTAINER_NAME=${CONTAINER_NAME-static-container-registry-test}
REGISTRY_HOST=${REGISTRY_HOST-127.0.0.1}
REGISTRY_PORT=${REGISTRY_PORT-5000}
REGISTRY="$REGISTRY_HOST:$REGISTRY_PORT"

TEST_DOCKER=${TEST_DOCKER:-1}
TEST_CONTAINERD=${TEST_CONTAINERD:-1}
TEST_CRIO=${TEST_CRIO:-1}
TEST_SKOPEO=${TEST_SKOPEO:-1}
TEST_ORAS=${TEST_ORAS:-1}

if [ "$TEST_DOCKER" -eq 1 ]; then
test_docker() {
        for image in ${AVAILABLE_IMAGES[*]}; do
                assert "$DOCKER pull '$REGISTRY/$image'"
        done
}
fi

if [ "$TEST_CONTAINERD" -eq 1 ]; then
test_containerd() {
        for image in ${AVAILABLE_IMAGES[*]}; do
                assert "sudo ${CRICTL} --image-endpoint unix:///run/containerd/containerd.sock pull '$REGISTRY/$image'"
        done
}
fi

if [ "$TEST_CRIO" -eq 1 ]; then
test_crio() {
        for image in ${AVAILABLE_IMAGES[*]}; do
                assert "sudo ${CRICTL} --image-endpoint unix:///run/crio/crio.sock pull '$REGISTRY/$image'"
        done
}
fi

if [ "$TEST_SKOPEO" -eq 1 ]; then
test_skopeo() {
        for image in ${AVAILABLE_IMAGES[*]}; do
                assert "$SKOPEO --debug inspect --tls-verify=false 'docker://$REGISTRY/$image'"
        done
}
fi

if [ "$TEST_ORAS" -eq 1 ]; then
test_oras() {
        assert "$ORAS pull '$REGISTRY/$AVAILABLE_FILE' -t text/plain"
        assert "test -f test.txt"
        assert_equals "$(cat test.txt)" "some content"
}
fi

setup_suite() {
        if [ "x$IMAGE" != "x" ]; then
                assert build_project_image
        fi
        if [ "x$IMAGES" != "x" ]; then
                assert create_images_directory
        fi
}

teardown_suite() {
        if [ "x$IMAGES" != "x" ]; then
                remove_images_directory
        fi
        if [ "x$IMAGE" != "x" ]; then
                delete_project_image
        fi
}

setup() {
        if [ "x$IMAGE" != "x" ]; then
                $DOCKER run \
                        -d \
                        -p "$REGISTRY:80" \
                        -v "$IMAGES:/var/lib/images:ro" \
                        --name "$CONTAINER_NAME" \
                        "$IMAGE" > /dev/null
        fi

        local i=600
        while [ $i -gt 0 ]; do
                local ok
                ok=$($CURL --silent "http://$REGISTRY/v2/" 2>/dev/null)
                if [ "x$ok" = 'xok' ]; then
                        i=0
                else
                        sleep 0.1
                        i=$((i - 1))
                fi
        done
}

teardown() {
        if [ "x$IMAGE" != "x" ]; then
                $DOCKER stop "$CONTAINER_NAME" > /dev/null
                $DOCKER rm "$CONTAINER_NAME" > /dev/null
        fi
}

build_project_image() {
        $DOCKER build -t "$IMAGE" .
}

delete_project_image() {
        $DOCKER rmi "$IMAGE" > /dev/null
}

AVAILABLE_IMAGES=(
    'alpine:3.9.3'
    'alpine:3.9'
    'alpine:3.8.4'
    'metalk8s-keepalived:latest'
)
AVAILABLE_FILE='file:latest'
create_images_directory() {
        mkdir "$IMAGES" "$IMAGES/alpine" "$IMAGES/metalk8s-keepalived"
        $SKOPEO copy --format v2s2 --dest-compress \
                docker://docker.io/alpine:3.9.3 \
                "dir:$IMAGES/alpine/3.9.3"
        $SKOPEO copy --format v2s2 --dest-compress \
                docker://docker.io/alpine:3.9 \
                "dir:$IMAGES/alpine/3.9"
        $DOCKER pull docker.io/alpine:3.8.4
        $SKOPEO copy --format v2s2 --dest-compress \
                docker-daemon:alpine:3.8.4 \
                "dir:$IMAGES/alpine/3.8.4"
        $DOCKER rmi docker.io/alpine:3.8.4
        $SKOPEO copy --format v2s2 --dest-compress \
                docker://docker.io/nicolast/metalk8s-keepalived:latest \
                "dir:$IMAGES/metalk8s-keepalived/latest"

        mkdir "$IMAGES/file" "$IMAGES/file/latest"
        echo -n '{}' > $IMAGES/file/latest/44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a
        echo -n 'some content' > $IMAGES/file/latest/290f493c44f5d63d06b374d0a5abd292fae38b92cab2fae5efefe1b0e9347f56
        cat <<EOF > $IMAGES/file/latest/manifest.json
 {
   "schemaVersion": 2,
   "mediaType": "application/vnd.oci.image.manifest.v1+json",
   "config": {
       "mediaType": "application/vnd.oci.image.config.v1+json",
        "digest": "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
        "size": 2
    },
   "layers": [
       {
            "mediaType": "text/plain",
            "digest": "sha256:290f493c44f5d63d06b374d0a5abd292fae38b92cab2fae5efefe1b0e9347f56",
            "size": 12,
            "annotations": {
                "org.opencontainers.image.title": "test.txt"
            }
        }
   ]
}
EOF

        $HARDLINK -c -vv "${IMAGES}"
}

remove_images_directory() {
        rm -rf "$IMAGES"
}
