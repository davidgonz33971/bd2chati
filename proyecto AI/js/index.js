// SLIDER
// Array with the paths of the images used in the slider
const images = [
    "../assets/slider1.jpg",
    "../assets/slider2.jpg",
    "../assets/slider3.jpg",
    "../assets/slider4.png",

];

// Variable that controls which image is currently being displayed
let index = 0;

// Selects the <img> element where the slider images will be shown
const slider = document.getElementById("slider-image");

// Changes the image automatically every 3 seconds
setInterval(() => {
    index++;
    if (index >= images.length) {
        index = 0;
    }
    slider.src = images[index];
}, 3000);

// Updates the current date and time on the page
function updateDateTime() {
    const el = document.getElementById("datetime");
    el.textContent = new Date().toLocaleString();
}

setInterval(updateDateTime, 1000);
updateDateTime();
