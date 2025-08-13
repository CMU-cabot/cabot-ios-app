: ${SRCROOT:=./}

TEMP_DIR=${TEMP_DIR:-/tmp}
DEST_DIR=${SRCROOT}/Resource/localserver/js/

download_and_copy() {
  local file_name=$1
  local url=$2

  local temp_file=${TEMP_DIR}/${file_name}
  curl -o "$temp_file" "$url"
  cp -f "$temp_file" "$DEST_DIR"
}

download_and_copy "three.min.js" "https://cdn.jsdelivr.net/npm/three@0.89.0/build/three.min.js"
download_and_copy "eventemitter2.min.js" "https://cdn.jsdelivr.net/npm/eventemitter2@6.4/lib/eventemitter2.min.js"

download_and_copy "roslib.js" "https://raw.githubusercontent.com/CMU-cabot/roslibjs/cabot-dev/build/roslib.js"
download_and_copy "ros3d.min.js" "https://raw.githubusercontent.com/CMU-cabot/ros3djs/cabot-ros2/build/ros3d.min.js"

download_and_copy "chart.js" "https://cdn.jsdelivr.net/npm/chart.js@4.5.0/dist/chart.umd.min.js"
download_and_copy "chartjs-adapter-date-fns.js" "https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3.0.0/dist/chartjs-adapter-date-fns.bundle.min.js"
download_and_copy "chartjs-plugin-streaming.js" "https://cdn.jsdelivr.net/npm/chartjs-plugin-streaming@2.0.0/dist/chartjs-plugin-streaming.min.js"
download_and_copy "date-fns.js" "https://cdn.jsdelivr.net/npm/date-fns@4.1.0/cdn.min.js"
