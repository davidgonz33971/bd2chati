// Array with the paths of the images used in the slider

const images = [
    "../assets/slider1.jpg",
    "../assets/slider2.jpg",
    "../assets/slider3.jpg",
    "../assets/slider4.png",

];

// Variable that controls which image is currently being displayed
let currentIndex = 0;

// Selects the <img> element where the slider images will be shown
const sliderImage = document.getElementById('slider-image');

// Changes the image automatically every 3 seconds
setInterval(() => {
    currentIndex = (currentIndex + 1) % images.length;

    sliderImage.style.opacity = 0;

    setTimeout(() => {
        sliderImage.src = images[currentIndex];
        sliderImage.style.opacity = 1;
    }, 300);

}, 4000);


// Updates the current date and time on the page
function updateDateTime() {
    const el = document.getElementById("datetime");
    el.textContent = new Date().toLocaleString();
}

setInterval(updateDateTime, 1000);
updateDateTime();