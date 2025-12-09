import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Calendar,
  MapPin,
  Clock,
  Users,
  Tag,
  Image as ImageIcon,
  Upload,
  Sparkles,
  Save,
  Eye,
  X,
  Loader2,
  CheckCircle,
  AlertCircle
} from 'lucide-react';
import { auth } from '../lib/supabase';
import { eventsService } from '../services/eventsService';
import { storageService } from '../services/storageService';
import { statusService } from '../services/statusService';
import { canCreateEvents, isOrganizer } from '../services/roleService';
import { verificationService } from '../services/verificationService';
import { useToast } from '../contexts/ToastContext';
import LocationSearch from '../components/LocationSearch';
import { DEPARTMENTS, getDepartmentName } from '../config/departments';

const EventCreation = () => {
  const navigate = useNavigate();
  const { error: showError } = useToast();
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    date: '',
    timeHour: '09',
    timeMinute: '00',
    timePeriod: 'AM',
    endTimeHour: '11',
    endTimeMinute: '00',
    endTimePeriod: 'AM',
    location: '',
    maxParticipants: '',
    category: '',
    tags: [],
    image: null,
    isVirtual: false,
    virtualLink: '',
    requirements: '',
    contactEmail: '',
    contactPhone: ''
  });

  const [aiSuggestions, setAiSuggestions] = useState([
    'Consider adding networking breaks for better engagement',
    'Based on similar events, 2-4 PM has highest attendance',
    'Include interactive elements like Q&A sessions',
    'Central locations see 25% higher registration rates'
  ]);

  const [currentStep, setCurrentStep] = useState(1);
  const [previewMode, setPreviewMode] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(false);
  const [user, setUser] = useState(null);
  const [imagePreview, setImagePreview] = useState(null);
  const [imageUploading, setImageUploading] = useState(false);
  const [isVerified, setIsVerified] = useState(null);
  const [showVerificationModal, setShowVerificationModal] = useState(false);

  const steps = [
    { number: 1, title: 'Basic Info', icon: Calendar },
    { number: 2, title: 'Details & Media', icon: MapPin },
    { number: 3, title: 'Additional Info', icon: Users },
    { number: 4, title: 'Review', icon: Eye }
  ];

  useEffect(() => {
    const checkUser = async () => {
      const { user } = await auth.getCurrentUser();
      if (!user) {
        navigate('/login');
        return;
      }
      setUser(user);

      // Check verification status
      const verified = await verificationService.isVerified(user.id);
      setIsVerified(verified);

      // If user is not verified, show modal (optional based on requirements, but good for UX)
      // For now, we allow creation but maybe warn or restricting later?
      // Re-reading file dump, it had verification check logic.
      // Assuming we enforce it if !verified
      if (!verified) {
        // setShowVerificationModal(true); // Uncomment if strict
      }
    };
    checkUser();
  }, [navigate]);

  const handleInputChange = (e) => {
    const { name, value, type, checked } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: type === 'checkbox' ? checked : value
    }));
  };

  const handleTagAdd = (tag) => {
    if (tag && !formData.tags.includes(tag)) {
      setFormData(prev => ({
        ...prev,
        tags: [...prev.tags, tag]
      }));
    }
  };

  const handleTagRemove = (tag) => {
    setFormData(prev => ({
      ...prev,
      tags: prev.tags.filter(t => t !== tag)
    }));
  };

  const handleImageUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    if (file.size > 5 * 1024 * 1024) {
      showError('Image size should be less than 5MB');
      return;
    }

    try {
      setImageUploading(true);
      const { data, error } = await storageService.uploadEventImage(file, user.id);

      if (error) throw error;

      setImagePreview(data.publicUrl);
      setFormData(prev => ({ ...prev, image: data.path, image_url: data.publicUrl }));
    } catch (err) {
      console.error('Error uploading image:', err);
      showError('Failed to upload image');
    } finally {
      setImageUploading(false);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!user) return;

    // Strict verification check before submit
    if (isVerified === false) {
      setShowVerificationModal(true);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      // Convert 12h time to 24h string for storage
      const formatTime24 = (hour, minute, period) => {
        let h = parseInt(hour);
        if (period === 'PM' && h < 12) h += 12;
        if (period === 'AM' && h === 12) h = 0;
        return `${h.toString().padStart(2, '0')}:${minute}`;
      };

      const eventData = {
        user_id: user.id,
        title: formData.title,
        description: formData.description,
        date: formData.date,
        time: formatTime24(formData.timeHour, formData.timeMinute, formData.timePeriod),
        end_time: formatTime24(formData.endTimeHour, formData.endTimeMinute, formData.endTimePeriod),
        location: formData.location,
        max_participants: formData.maxParticipants ? parseInt(formData.maxParticipants) : null,
        category: formData.category, // Storing Department ID here
        tags: formData.tags,
        image_url: formData.image_url, // Storing the public URL
        is_virtual: formData.isVirtual,
        virtual_link: formData.isVirtual ? formData.virtualLink : null,
        requirements: formData.requirements,
        contact_email: formData.contactEmail,
        contact_phone: formData.contactPhone,
        status: 'upcoming'
      };

      const { data, error } = await eventsService.createEvent(eventData);

      if (error) throw error;

      setSuccess(true);
      setTimeout(() => {
        navigate(`/events/${data.id}`);
      }, 2000);
    } catch (err) {
      console.error('Error creating event:', err);
      setError(err.message || 'Failed to create event');
    } finally {
      setLoading(false);
    }
  };

  const renderStepContent = () => {
    switch (currentStep) {
      case 1:
        return (
          <div className="space-y-4 sm:space-y-6">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Event Title *
              </label>
              <input
                type="text"
                name="title"
                value={formData.title}
                onChange={handleInputChange}
                className="input-field w-full"
                placeholder="e.g., Annual Tech Summit 2024"
                required
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Description *
              </label>
              <textarea
                name="description"
                value={formData.description}
                onChange={handleInputChange}
                rows={4}
                className="input-field w-full"
                placeholder="Describe your event..."
                required
              />
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Date *
                </label>
                <input
                  type="date"
                  name="date"
                  value={formData.date}
                  onChange={handleInputChange}
                  min={new Date().toISOString().split('T')[0]}
                  className="input-field w-full"
                  required
                />
              </div>

              <div className="flex gap-2">
                <div className="flex-1">
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Start Time *
                  </label>
                  <div className="flex gap-1">
                    <select
                      name="timeHour"
                      value={formData.timeHour}
                      onChange={handleInputChange}
                      className="input-field w-full p-1"
                    >
                      {Array.from({ length: 12 }, (_, i) => i + 1).map(h => (
                        <option key={h} value={h.toString().padStart(2, '0')}>{h}</option>
                      ))}
                    </select>
                    <select
                      name="timeMinute"
                      value={formData.timeMinute}
                      onChange={handleInputChange}
                      className="input-field w-full p-1"
                    >
                      {['00', '15', '30', '45'].map(m => (
                        <option key={m} value={m}>{m}</option>
                      ))}
                    </select>
                    <select
                      name="timePeriod"
                      value={formData.timePeriod}
                      onChange={handleInputChange}
                      className="input-field w-full p-1"
                    >
                      <option value="AM">AM</option>
                      <option value="PM">PM</option>
                    </select>
                  </div>
                </div>

                <div className="flex-1">
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    End Time *
                  </label>
                  <div className="flex gap-1">
                    <select
                      name="endTimeHour"
                      value={formData.endTimeHour}
                      onChange={handleInputChange}
                      className="input-field w-full p-1"
                    >
                      {Array.from({ length: 12 }, (_, i) => i + 1).map(h => (
                        <option key={h} value={h.toString().padStart(2, '0')}>{h}</option>
                      ))}
                    </select>
                    <select
                      name="endTimeMinute"
                      value={formData.endTimeMinute}
                      onChange={handleInputChange}
                      className="input-field w-full p-1"
                    >
                      {['00', '15', '30', '45'].map(m => (
                        <option key={m} value={m}>{m}</option>
                      ))}
                    </select>
                    <select
                      name="endTimePeriod"
                      value={formData.endTimePeriod}
                      onChange={handleInputChange}
                      className="input-field w-full p-1"
                    >
                      <option value="AM">AM</option>
                      <option value="PM">PM</option>
                    </select>
                  </div>
                </div>
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Department *
              </label>
              <select
                name="category"
                value={formData.category}
                onChange={handleInputChange}
                className="input-field w-full"
                required
              >
                <option value="">Select department</option>
                {DEPARTMENTS.map(dept => (
                  <option key={dept.id} value={dept.id}>{dept.name}</option>
                ))}
              </select>
            </div>
          </div>
        );

      case 2:
        return (
          <div className="space-y-4 sm:space-y-6">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Location * <span className="text-xs text-gray-500 font-normal">(Philippines only)</span>
              </label>
              <LocationSearch
                value={formData.location}
                onChange={(location) => setFormData(prev => ({ ...prev, location }))}
                placeholder="Search for specific venues, buildings, or addresses..."
                required
              />
              <p className="mt-2 text-xs text-gray-500 break-words">
                Start typing to search for specific venues, buildings, or addresses (e.g., "SM Megamall", "Ayala Center", "123 Rizal Avenue").
              </p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Maximum Participants
                </label>
                <input
                  type="number"
                  name="maxParticipants"
                  value={formData.maxParticipants}
                  onChange={handleInputChange}
                  className="input-field w-full"
                  placeholder="Enter max participants"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Tags
                </label>
                <input
                  type="text"
                  onKeyPress={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      handleTagAdd(e.target.value);
                      e.target.value = '';
                    }
                  }}
                  className="input-field w-full"
                  placeholder="Press Enter to add tags"
                />
              </div>
            </div>

            {formData.tags.length > 0 && (
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Added Tags
                </label>
                <div className="flex flex-wrap gap-2">
                  {formData.tags.map(tag => (
                    <span
                      key={tag}
                      className="inline-flex items-center px-3 py-1 rounded-full text-sm bg-primary-100 text-primary-800"
                    >
                      {tag}
                      <button
                        type="button"
                        onClick={() => handleTagRemove(tag)}
                        className="ml-2 text-primary-600 hover:text-primary-800"
                      >
                        <X size={16} />
                      </button>
                    </span>
                  ))}
                </div>
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Event Image
              </label>
              <div className="border-2 border-dashed border-gray-300 rounded-lg p-4 sm:p-6 text-center">
                {imagePreview ? (
                  <div className="space-y-4">
                    <img
                      src={imagePreview}
                      alt="Event preview"
                      className="mx-auto h-24 sm:h-32 w-36 sm:w-48 object-cover rounded-lg"
                    />
                    <div className="flex justify-center space-x-2">
                      <button
                        type="button"
                        onClick={() => {
                          setImagePreview(null);
                          setFormData(prev => ({ ...prev, image: null, image_url: null }));
                        }}
                        className="text-red-600 hover:text-red-800 text-sm"
                      >
                        Remove Image
                      </button>
                    </div>
                  </div>
                ) : (
                  <>
                    <Upload className="mx-auto h-10 w-10 sm:h-12 sm:w-12 text-gray-400" />
                    <div className="mt-4">
                      <input
                        type="file"
                        accept="image/*"
                        onChange={handleImageUpload}
                        className="hidden"
                        id="image-upload"
                        disabled={imageUploading}
                      />
                      <label
                        htmlFor="image-upload"
                        className={`cursor-pointer inline-block px-4 py-2 rounded-lg text-sm sm:text-base ${imageUploading
                          ? 'bg-gray-400 text-white cursor-not-allowed'
                          : 'bg-primary-600 text-white hover:bg-primary-700'
                          }`}
                      >
                        {imageUploading ? (
                          <div className="flex items-center">
                            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                            Processing...
                          </div>
                        ) : (
                          'Upload Image'
                        )}
                      </label>
                    </div>
                    <p className="mt-2 text-xs sm:text-sm text-gray-500">
                      PNG, JPG, GIF up to 5MB
                    </p>
                  </>
                )}
              </div>
            </div>

            <div className="flex items-center space-x-3">
              <input
                type="checkbox"
                name="isVirtual"
                checked={formData.isVirtual}
                onChange={handleInputChange}
                className="h-4 w-4 text-primary-600 focus:ring-primary-500 border-gray-300 rounded"
              />
              <label className="text-sm font-medium text-gray-700">
                This is a virtual event
              </label>
            </div>

            {formData.isVirtual && (
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Virtual Meeting Link
                </label>
                <input
                  type="url"
                  name="virtualLink"
                  value={formData.virtualLink}
                  onChange={handleInputChange}
                  className="input-field w-full"
                  placeholder="https://meet.google.com/..."
                />
              </div>
            )}
          </div>
        );

      case 3:
        return (
          <div className="space-y-4 sm:space-y-6">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Requirements
              </label>
              <textarea
                name="requirements"
                value={formData.requirements}
                onChange={handleInputChange}
                rows={3}
                className="input-field w-full"
                placeholder="Any special requirements for participants..."
              />
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Contact Email *
                </label>
                <input
                  type="email"
                  name="contactEmail"
                  value={formData.contactEmail}
                  onChange={handleInputChange}
                  className="input-field w-full"
                  placeholder="contact@example.com"
                  required
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Contact Phone
                </label>
                <input
                  type="tel"
                  name="contactPhone"
                  value={formData.contactPhone}
                  onChange={handleInputChange}
                  className="input-field w-full"
                  placeholder="+1 (555) 123-4567"
                />
              </div>
            </div>

            <div className="bg-blue-50 p-3 sm:p-4 rounded-lg">
              <h4 className="font-medium text-blue-900 mb-2 text-sm sm:text-base">AI-Powered Suggestions</h4>
              <ul className="space-y-2">
                {aiSuggestions.map((suggestion, index) => (
                  <li key={index} className="flex items-start space-x-2 text-xs sm:text-sm text-blue-800">
                    <Sparkles size={14} className="text-blue-600 mt-0.5 flex-shrink-0" />
                    <span className="break-words">{suggestion}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        );

      case 4:
        return (
          <div className="space-y-4 sm:space-y-6">
            <div className="bg-gray-50 p-4 sm:p-6 rounded-lg">
              <h3 className="text-base sm:text-lg font-semibold text-gray-900 mb-4">Event Preview</h3>
              <div className="space-y-4">
                <div>
                  <h4 className="font-medium text-gray-900 break-words">{formData.title || 'Event Title'}</h4>
                  <p className="text-sm text-gray-600 break-words">{formData.description || 'Event description will appear here...'}</p>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4 text-sm">
                  <div className="flex flex-col sm:flex-row sm:items-center gap-1">
                    <span className="font-medium text-gray-700">Date:</span>
                    <span className="text-gray-600">{formData.date || 'Not set'}</span>
                  </div>
                  <div className="flex flex-col sm:flex-row sm:items-center gap-1">
                    <span className="font-medium text-gray-700">Start Time:</span>
                    <span className="text-gray-600">{formData.timeHour}:{formData.timeMinute} {formData.timePeriod}</span>
                  </div>
                  <div className="flex flex-col sm:flex-row sm:items-center gap-1">
                    <span className="font-medium text-gray-700">End Time:</span>
                    <span className="text-gray-600">{formData.endTimeHour}:{formData.endTimeMinute} {formData.endTimePeriod}</span>
                  </div>
                  <div className="flex flex-col sm:flex-row sm:items-start gap-1">
                    <span className="font-medium text-gray-700">Location:</span>
                    <span className="text-gray-600 break-words">{formData.location || 'Not set'}</span>
                  </div>
                  <div className="flex flex-col sm:flex-row sm:items-center gap-1">
                    <span className="font-medium text-gray-700">Department:</span>
                    <span className="text-gray-600">{getDepartmentName(formData.category) || 'Not set'}</span>
                  </div>
                </div>
              </div>

              <div className="flex items-center space-x-3">
                <input
                  type="checkbox"
                  id="publish-now"
                  className="h-4 w-4 text-primary-600 focus:ring-primary-500 border-gray-300 rounded flex-shrink-0"
                  defaultChecked
                />
                <label htmlFor="publish-now" className="text-sm font-medium text-gray-700">
                  Publish event immediately
                </label>
              </div>

              <div className="bg-yellow-50 p-3 sm:p-4 rounded-lg">
                <h4 className="font-medium text-yellow-900 mb-2 text-sm sm:text-base">Before Publishing</h4>
                <ul className="text-xs sm:text-sm text-yellow-800 space-y-1">
                  <li>• Review all event details carefully</li>
                  <li>• Ensure contact information is correct</li>
                  <li>• Check that date and time are accurate</li>
                  <li>• Verify location details</li>
                </ul>
              </div>
            </div>
          </div>
        );

      default:
        return null;
    }
  };

  return (
    <div className="max-w-7xl mx-auto space-y-4 sm:space-y-6">
      <div className="flex flex-col sm:flex-row sm:justify-between sm:items-center gap-4 sm:gap-0">
        <div className="min-w-0 flex-1">
          <h1 className="text-2xl sm:text-3xl font-bold text-gray-900 break-words">Create New Event</h1>
          <p className="text-sm sm:text-base text-gray-600 mt-1 break-words">Set up your event with AI-powered suggestions and smart features</p>
        </div>
        <div className="flex flex-wrap gap-2 sm:gap-3">
          <button
            onClick={() => {
              if (previewMode) {
                setPreviewMode(false);
                setCurrentStep(1); // Go back to start if exiting preview? Or just toggle logic
                // For simplicity, just toggle local preview state, but here we use steps. 
                // Let's assume previewMode button just toggles but we rely on steps mostly.
                // Actually, step 4 IS preview. 
                if (currentStep === 4) setCurrentStep(1);
              } else {
                setPreviewMode(true);
                setCurrentStep(4);
              }
            }}
            className="btn-secondary flex items-center text-sm sm:text-base"
          >
            <Eye size={18} className="mr-2 flex-shrink-0" />
            <span>{currentStep === 4 ? 'Edit Mode' : 'Preview'}</span>
          </button>
          <button
            onClick={() => navigate('/events')}
            className="btn-secondary flex items-center text-sm sm:text-base"
          >
            <Save size={18} className="mr-2 flex-shrink-0" />
            <span>Cancel</span>
          </button>
        </div>
      </div>

      {success && (
        <div className="bg-green-50 border border-green-200 rounded-lg p-6 text-center">
          <div className="flex justify-center mb-4">
            <CheckCircle className="h-12 w-12 text-green-500" />
          </div>
          <h3 className="text-lg font-semibold text-green-800 mb-2">
            Event Created Successfully!
          </h3>
          <p className="text-green-700 mb-4">
            Your event has been created and is now live. Redirecting you to the events page...
          </p>
          <div className="flex justify-center">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-green-600"></div>
          </div>
        </div>
      )}

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4">
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <X className="h-5 w-5 text-red-400" />
            </div>
            <div className="ml-3">
              <p className="text-sm text-red-800">{error}</p>
            </div>
          </div>
        </div>
      )}

      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4 sm:p-6">
        <div className="sm:hidden mb-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-gray-600">Step {currentStep} of {steps.length}</span>
            <span className="text-sm font-medium text-primary-600">{steps[currentStep - 1].title}</span>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-2">
            <div
              className="bg-primary-500 h-2 rounded-full transition-all duration-300"
              style={{ width: `${(currentStep / steps.length) * 100}%` }}
            />
          </div>
        </div>

        <div className="hidden sm:block">
          <div className="flex items-center justify-between mb-6">
            {steps.map((step, index) => (
              <div key={step.number} className="flex items-center">
                <div className={`flex items-center justify-center w-10 h-10 rounded-full border-2 ${currentStep >= step.number
                  ? 'border-primary-500 bg-primary-500 text-white'
                  : 'border-gray-300 text-gray-500'
                  }`}>
                  {currentStep > step.number ? (
                    <span className="text-sm font-medium">✓</span>
                  ) : (
                    <step.icon size={20} />
                  )}
                </div>
                {index < steps.length - 1 && (
                  <div className={`w-12 lg:w-16 h-0.5 mx-2 lg:mx-4 ${currentStep > step.number ? 'bg-primary-500' : 'bg-gray-300'
                    }`} />
                )}
              </div>
            ))}
          </div>

          <div className="text-center">
            <h2 className="text-xl font-semibold text-gray-900">
              {steps[currentStep - 1].title}
            </h2>
            <p className="text-gray-600 mt-1">
              Step {currentStep} of {steps.length}
            </p>
          </div>
        </div>
      </div>

      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4 sm:p-6">
        <form onSubmit={handleSubmit}>
          {renderStepContent()}

          <div className="flex flex-col-reverse sm:flex-row sm:justify-between gap-3 mt-6 sm:mt-8 pt-4 sm:pt-6 border-t border-gray-200">
            <button
              type="button"
              onClick={() => setCurrentStep(Math.max(1, currentStep - 1))}
              disabled={currentStep === 1}
              className="btn-secondary disabled:opacity-50 disabled:cursor-not-allowed w-full sm:w-auto"
            >
              Previous
            </button>

            <div className="flex flex-col sm:flex-row gap-2 sm:gap-3">
              {currentStep < steps.length ? (
                <button
                  type="button"
                  onClick={() => setCurrentStep(currentStep + 1)}
                  className="btn-primary w-full sm:w-auto"
                >
                  Next Step
                </button>
              ) : (
                <button
                  type="submit"
                  className="btn-primary flex items-center justify-center w-full sm:w-auto"
                  disabled={loading}
                >
                  {loading ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Creating Event...
                    </>
                  ) : (
                    'Create Event'
                  )}
                </button>
              )}
            </div>
          </div>
        </form>

        {showVerificationModal && (
          <div
            className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-[100] px-4"
            onClick={(e) => {
              if (e.target === e.currentTarget) {
                setShowVerificationModal(false);
              }
            }}
          >
            <div
              className="bg-white rounded-lg p-6 max-w-md w-full relative"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center">
                  <AlertCircle className="text-yellow-500 mr-3" size={24} />
                  <h3 className="text-lg font-semibold">Verification Required</h3>
                </div>
                <button
                  onClick={() => setShowVerificationModal(false)}
                  className="text-gray-400 hover:text-gray-600"
                >
                  <X size={20} />
                </button>
              </div>

              <div className="mb-6">
                <p className="text-gray-700 mb-4">
                  You need to verify your identity before you can create events. This helps ensure a safe and secure experience for all participants.
                </p>
                <div className="flex space-x-3">
                  <button
                    onClick={() => setShowVerificationModal(false)}
                    className="flex-1 px-4 py-2 border border-gray-300 rounded-lg font-medium text-gray-700 hover:bg-gray-50 transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={() => {
                      setShowVerificationModal(false);
                      navigate('/settings?tab=verification');
                    }}
                    className="flex-1 px-4 py-2 bg-primary-600 text-white rounded-lg font-medium hover:bg-primary-700 transition-colors"
                  >
                    Go to Verification
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default EventCreation;
