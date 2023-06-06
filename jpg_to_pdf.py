import os
from PIL import Image
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import letter

# Path to the folder with images
img_dir = '/home/ac/Pictures/kids_pics/folder_1/'

# Size of the paper (default is letter size)
paper_width, paper_height = letter

# Output PDF path
output_pdf_path = '/home/ac/Pictures/kids_pics/folder_1.pdf'

# Create a canvas for the PDF
c = canvas.Canvas(output_pdf_path, pagesize=(paper_width, paper_height))

# List all jpg files in the directory
file_list = [f for f in os.listdir(img_dir) if f.endswith('.jpg')]

# Sort the files by name (optional)
file_list.sort()

# Calculate the number of images per page
images_per_page = 4  # This should remain at 4 for a 2x2 grid

# Calculate image size (arranged in a 2x2 grid)
img_width = paper_width / 2
img_height = paper_height / 2

# Counter for the current image
img_counter = 0

for img_file in file_list:
    # Open the image file
    with Image.open(os.path.join(img_dir, img_file)) as img:
        # Calculate scale factors (maintaining aspect ratio)
        width_scale = img_width / img.width
        height_scale = img_height / img.height
        scale = min(width_scale, height_scale)

        # Calculate new image size
        new_width = int(img.width * scale)
        new_height = int(img.height * scale)

        # Resize the image
        img = img.resize((new_width, new_height), Image.LANCZOS)

        # Calculate the position of the image on the paper (centered in each quadrant)
        pos_x = (img_counter % 2) * img_width + (img_width - new_width) / 2
        pos_y = paper_height - ((img_counter // 2 + 1) * img_height) + (img_height - new_height) / 2

        # Draw the image on the PDF
        c.drawInlineImage(img, pos_x, pos_y, width=new_width, height=new_height)

    img_counter += 1

    # When we've drawn the correct number of images on the page, move to the next page
    if img_counter % images_per_page == 0:
        c.showPage()
        # Reset the counter
        img_counter = 0

# If there are leftover images that did not fill up the last page, we still need to save the page
if img_counter % images_per_page != 0:
    c.showPage()

# Save the PDF
c.save()

